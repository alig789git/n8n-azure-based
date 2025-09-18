# deploy-n8n.sh
#!/bin/bash

set -e

echo "🔧 Deploying n8n to AKS"
echo "======================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    print_error "kubectl is not configured. Please run setup-infrastructure.sh first."
    exit 1
fi

# Install NGINX Ingress Controller
print_status "Installing NGINX Ingress Controller..."
if ! kubectl get namespace ingress-nginx &> /dev/null; then
    kubectl create namespace ingress-nginx
fi

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

if ! helm list -n ingress-nginx | grep -q ingress-nginx; then
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --set controller.service.type=LoadBalancer \
        --set controller.service.externalTrafficPolicy=Local
else
    print_status "NGINX Ingress Controller already installed."
fi

# Install cert-manager for SSL certificates
print_status "Installing cert-manager..."
if ! kubectl get namespace cert-manager &> /dev/null; then
    kubectl create namespace cert-manager
fi

helm repo add jetstack https://charts.jetstack.io
helm repo update

if ! helm list -n cert-manager | grep -q cert-manager; then
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version v1.13.0 \
        --set installCRDs=true
else
    print_status "cert-manager already installed."
fi

# Create Let's Encrypt ClusterIssuer
print_status "Creating Let's Encrypt ClusterIssuer..."
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com  # Change this to your email
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

# Update secrets with values from Key Vault
print_status "Updating secrets from Azure Key Vault..."

# Get Key Vault name from Terraform outputs
cd terraform/
KEY_VAULT_NAME=$(terraform output -raw key_vault_name)
cd ..

if [[ -n "$KEY_VAULT_NAME" ]]; then
    # Get secrets from Key Vault
    DB_CONNECTION=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name postgres-connection-string --query value -o tsv)
    ENCRYPTION_KEY=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name n8n-encryption-key --query value -o tsv)
    
    # Extract database credentials
    DB_USER=$(echo "$DB_CONNECTION" | sed -n 's/.*:\/\/\([^:]*\):.*/\1/p')
    DB_PASSWORD=$(echo "$DB_CONNECTION" | sed -n 's/.*:\/\/[^:]*:\([^@]*\)@.*/\1/p')
    
    # Update secret manifest
    sed -i "s/ChangeMePlease123!/$DB_PASSWORD/g" k8s-manifests/secret.yaml
    sed -i "s/n8n-encryption-key-placeholder/$ENCRYPTION_KEY/g" k8s-manifests/secret.yaml
    sed -i "s/n8nadmin/$DB_USER/g" k8s-manifests/secret.yaml
else
    print_warning "Could not retrieve Key Vault name. Please update secrets manually."
fi

# Deploy n8n
print_status "Deploying n8n application..."

# Apply manifests in order
kubectl apply -f k8s-manifests/namespace.yaml
kubectl apply -f k8s-manifests/configmap.yaml
kubectl apply -f k8s-manifests/secret.yaml
kubectl apply -f k8s-manifests/service-account.yaml
kubectl apply -f k8s-manifests/pvc.yaml

# Wait for PVCs to be bound
print_status "Waiting for persistent volumes to be ready..."
kubectl wait --for=condition=Bound pvc/n8n-data-pvc -n n8n --timeout=60s
kubectl wait --for=condition=Bound pvc/n8n-files-pvc -n n8n --timeout=60s

# Deploy application
kubectl apply -f k8s-manifests/n8n-deployment.yaml
kubectl apply -f k8s-manifests/n8n-service.yaml
kubectl apply -f k8s-manifests/n8n-ingress.yaml
kubectl apply -f k8s-manifests/hpa.yaml
kubectl apply -f k8s-manifests/network-policy.yaml
kubectl apply -f k8s-manifests/pod-disruption-budget.yaml

# Wait for deployment to be ready
print_status "Waiting for n8n deployment to be ready..."
kubectl wait --for=condition=available deployment/n8n -n n8n --timeout=300s

print_status "n8n deployed successfully!"

# Get external IP
print_status "Getting external IP address..."
EXTERNAL_IP=""
while [[ -z "$EXTERNAL_IP" ]]; do
    print_status "Waiting for external IP..."
    EXTERNAL_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}")
    sleep 10
done

print_status "External IP: $EXTERNAL_IP"
print_status "Please update your DNS to point n8n.demo.example.com to $EXTERNAL_IP"

# Run health check
print_status "Running health check..."
chmod +x tests/health-check.sh
kubectl port-forward svc/n8n-service 8080:80 -n n8n &
PORTFORWARD_PID=$!

sleep 10
export N8N_ENDPOINT="http://localhost:8080"
if bash tests/health-check.sh; then
    print_status "✅ n8n is healthy and ready to use!"
else
    print_warning "⚠️  Health check failed. Please check the logs."
fi

kill $PORTFORWARD_PID

print_status "Deployment completed!"
print_status "Access n8n at: https://n8n.demo.example.com (after DNS configuration)"