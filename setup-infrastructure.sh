# setup-infrastructure.sh
#!/bin/bash

set -e

echo "🚀 Setting up n8n on AKS Infrastructure"
echo "======================================="

# Configuration
RESOURCE_GROUP="rg-n8n-demo"
LOCATION="westeurope"
TERRAFORM_STATE_STORAGE="stterraformstate"
TERRAFORM_STATE_CONTAINER="tfstate"

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

# Check prerequisites
print_status "Checking prerequisites..."

# Check if Azure CLI is installed and logged in
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

if ! az account show &> /dev/null; then
    print_error "You are not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed. Please install it first."
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_warning "kubectl is not installed. You'll need it to manage the cluster."
fi

print_status "Prerequisites check completed."

# Create Terraform backend storage
print_status "Setting up Terraform backend storage..."

# Create resource group for Terraform state
if ! az group show --name "rg-terraform-state" &> /dev/null; then
    print_status "Creating resource group for Terraform state..."
    az group create --name "rg-terraform-state" --location "$LOCATION"
else
    print_status "Terraform state resource group already exists."
fi

# Create storage account for Terraform state
if ! az storage account show --name "$TERRAFORM_STATE_STORAGE" --resource-group "rg-terraform-state" &> /dev/null; then
    print_status "Creating storage account for Terraform state..."
    az storage account create \
        --name "$TERRAFORM_STATE_STORAGE" \
        --resource-group "rg-terraform-state" \
        --location "$LOCATION" \
        --sku "Standard_LRS" \
        --encryption-services blob
else
    print_status "Terraform state storage account already exists."
fi

# Create container for Terraform state
STORAGE_KEY=$(az storage account keys list --resource-group "rg-terraform-state" --account-name "$TERRAFORM_STATE_STORAGE" --query '[0].value' -o tsv)

if ! az storage container show --name "$TERRAFORM_STATE_CONTAINER" --account-name "$TERRAFORM_STATE_STORAGE" --account-key "$STORAGE_KEY" &> /dev/null; then
    print_status "Creating container for Terraform state..."
    az storage container create \
        --name "$TERRAFORM_STATE_CONTAINER" \
        --account-name "$TERRAFORM_STATE_STORAGE" \
        --account-key "$STORAGE_KEY"
else
    print_status "Terraform state container already exists."
fi

# Initialize Terraform
print_status "Initializing Terraform..."
cd terraform/

terraform init \
    -backend-config="resource_group_name=rg-terraform-state" \
    -backend-config="storage_account_name=$TERRAFORM_STATE_STORAGE" \
    -backend-config="container_name=$TERRAFORM_STATE_CONTAINER" \
    -backend-config="key=n8n-demo.tfstate"

# Validate Terraform configuration
print_status "Validating Terraform configuration..."
terraform validate

# Create terraform.tfvars if it doesn't exist
if [[ ! -f "terraform.tfvars" ]]; then
    print_warning "terraform.tfvars not found. Creating from example..."
    cp terraform.tfvars.example terraform.tfvars
    print_warning "Please edit terraform.tfvars with your specific values before proceeding."
    print_warning "Especially update the postgres_admin_password!"
    exit 1
fi

# Plan Terraform deployment
print_status "Planning Terraform deployment..."
terraform plan -out=tfplan

# Ask for confirmation
echo ""
read -p "Do you want to apply the Terraform plan? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Apply Terraform configuration
    print_status "Applying Terraform configuration..."
    terraform apply tfplan
    
    print_status "Terraform deployment completed successfully!"
    
    # Get AKS credentials
    print_status "Configuring kubectl..."
    CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
    RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
    
    az aks get-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$CLUSTER_NAME"
    
    print_status "Infrastructure setup completed!"
    print_status "Next steps:"
    echo "1. Deploy n8n using: kubectl apply -f ../k8s-manifests/"
    echo "2. Install NGINX Ingress Controller"
    echo "3. Configure DNS for your domain"
    echo "4. Set up monitoring with Prometheus/Grafana"
    
else
    print_status "Terraform deployment cancelled."
fi