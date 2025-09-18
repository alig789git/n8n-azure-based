# n8n на AKS - Полное руководство по развертыванию

## Обзор проекта

Этот проект демонстрирует развертывание n8n (инструмент автоматизации процессов) в Azure Kubernetes Service с использованием GitOps подхода через ArgoCD.

### Архитектура

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Azure DevOps  │───▶│       AKS        │───▶│  PostgreSQL DB  │
│    Pipeline     │    │   (n8n + ArgoCD) │    │   (Azure DB)    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │  Azure Key      │
                       │     Vault       │
                       └─────────────────┘
```

## Структура проекта

```
n8n-aks-deployment/
├── terraform/                  # Инфраструктура как код
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
├── k8s-manifests/             # Kubernetes манифесты
│   ├── namespace.yaml
│   ├── n8n-deployment.yaml
│   ├── n8n-service.yaml
│   ├── n8n-ingress.yaml
│   ├── postgres-secret.yaml
│   └── argocd/
│       ├── application.yaml
│       └── appproject.yaml
├── monitoring/                # Мониторинг и наблюдаемость
│   ├── prometheus-config.yaml
│   └── grafana-dashboard.json
├── tests/                     # Автоматические тесты
│   ├── health-check.sh
│   └── integration-tests.yaml
├── azure-pipelines.yml        # CI/CD пайплайн
└── README.md
```

## Предварительные требования

### Необходимые инструменты
- Azure CLI (версия 2.50+)
- kubectl (версия 1.25+)
- Terraform (версия 1.5+)
- Helm (версия 3.12+)

### Подготовка Azure
```bash
# Авторизация в Azure
az login

# Создание Resource Group
az group create --name rg-n8n-demo --location westeurope

# Создание Service Principal для Terraform
az ad sp create-for-rbac --name "sp-n8n-terraform" \
  --role="Contributor" \
  --scopes="/subscriptions/YOUR_SUBSCRIPTION_ID"
```

## Этап 1: Развертывание инфраструктуры

### Terraform конфигурация

Основные ресурсы создаваемые Terraform:
- AKS кластер с System Node Pool
- Azure Database for PostgreSQL
- Azure Key Vault
- Azure Container Registry
- Networking (VNet, Subnets)

### Команды развертывания

```bash
cd terraform/

# Инициализация
terraform init

# Планирование
terraform plan -var="environment=demo" -var="location=westeurope"

# Применение
terraform apply -var="environment=demo" -var="location=westeurope"
```

## Этап 2: Настройка Kubernetes

### Подключение к AKS
```bash
# Получение credentials
az aks get-credentials --resource-group rg-n8n-demo --name aks-n8n-demo

# Проверка подключения
kubectl get nodes
```

### Установка ArgoCD
```bash
# Создание namespace
kubectl create namespace argocd

# Установка ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Получение пароля для ArgoCD
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Этап 3: Развертывание n8n

### Конфигурация n8n
- **Версия**: n8n:1.0.0
- **Порт**: 5678
- **База данных**: PostgreSQL (Azure Database)
- **Хранилище**: Azure Blob Storage для файлов

### Переменные окружения
```yaml
N8N_DATABASE_TYPE: postgresdb
N8N_DATABASE_HOST: postgresql-n8n-demo.postgres.database.azure.com
N8N_DATABASE_PORT: 5432
N8N_DATABASE_NAME: n8n
N8N_DATABASE_USER: n8nadmin
N8N_ENCRYPTION_KEY: # Из Azure Key Vault
N8N_USER_MANAGEMENT_DISABLED: false
N8N_DEFAULT_BINARY_DATA_MODE: filesystem
```

### Применение манифестов
```bash
# Создание namespace
kubectl apply -f k8s-manifests/namespace.yaml

# Применение секретов
kubectl apply -f k8s-manifests/postgres-secret.yaml

# Развертывание n8n
kubectl apply -f k8s-manifests/n8n-deployment.yaml
kubectl apply -f k8s-manifests/n8n-service.yaml
kubectl apply -f k8s-manifests/n8n-ingress.yaml
```

## Этап 4: Настройка мониторинга

### Prometheus и Grafana
```bash
# Добавление Helm репозитория
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Установка Prometheus
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values monitoring/prometheus-values.yaml
```

### Метрики для отслеживания
- Время отклика n8n API
- Количество выполненных workflow
- Использование ресурсов (CPU, Memory)
- Статус подключения к PostgreSQL

## Этап 5: CI/CD с Azure DevOps

### Пайплайн включает:
1. **Build Stage**: Проверка Terraform и YAML
2. **Test Stage**: Линтинг и валидация
3. **Deploy Stage**: Применение изменений
4. **Verify Stage**: Проверка работоспособности

### Переменные пайплайна
```yaml
variables:
  azureServiceConnection: 'Azure-Service-Connection'
  resourceGroupName: 'rg-n8n-demo'
  aksClusterName: 'aks-n8n-demo'
  acrName: 'acrn8ndemo'
```

## Безопасность

### Управление секретами
- Все чувствительные данные в Azure Key Vault
- Использование Managed Identity для доступа
- Шифрование данных в покое и в движении

### Сетевая безопасность
- Private endpoints для PostgreSQL
- Network Security Groups
- Azure Firewall для исходящего трафика

## Тестирование

### Health Check
```bash
#!/bin/bash
# tests/health-check.sh

ENDPOINT="https://n8n.demo.example.com/healthz"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" $ENDPOINT)

if [ $RESPONSE -eq 200 ]; then
    echo "✅ n8n is healthy"
    exit 0
else
    echo "❌ n8n health check failed (HTTP $RESPONSE)"
    exit 1
fi
```

### Integration Tests
- Создание тестового workflow
- Проверка подключения к внешним API
- Валидация сохранения данных в PostgreSQL

## Оптимизация затрат

### Рекомендации для демо-среды
- Использование Azure Spot Instances для worker nodes
- Автоматическое масштабирование AKS (1-3 ноды)
- Настройка автоматического выключения вне рабочих часов
- Мониторинг затрат через Azure Cost Management

### Ожидаемые месячные затраты
- AKS кластер (2 ноды B2s): ~$60
- PostgreSQL (Basic tier): ~$25
- Key Vault: ~$2
- Networking: ~$5
- **Итого**: ~$92/месяц

## Мониторинг и алерты

### Ключевые метрики
1. **Доступность**: Uptime n8n сервиса
2. **Производительность**: Время выполнения workflow
3. **Ошибки**: Количество неудачных executions
4. **Ресурсы**: Использование CPU/Memory

### Alerting правила
```yaml
# Пример alert для высокой нагрузки
- alert: N8nHighCPUUsage
  expr: rate(container_cpu_usage_seconds_total{pod=~"n8n-.*"}[5m]) > 0.8
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "n8n pod has high CPU usage"
```

## Масштабирование

### Horizontal Pod Autoscaler
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: n8n-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: n8n
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## Устранение неполадок

### Часто встречающиеся проблемы

1. **Pod не запускается**
   ```bash
   kubectl describe pod n8n-xxx-xxx
   kubectl logs n8n-xxx-xxx
   ```

2. **Проблемы с подключением к PostgreSQL**
   ```bash
   kubectl exec -it n8n-xxx-xxx -- sh
   pg_isready -h postgresql-host -p 5432
   ```

3. **ArgoCD не синхронизирует**
   ```bash
   kubectl logs -n argocd deployment/argocd-application-controller
   ```

### Полезные команды
```bash
# Проверка статуса всех ресурсов
kubectl get all -n n8n

# Просмотр событий
kubectl get events -n n8n --sort-by='.lastTimestamp'

# Проверка секретов
kubectl get secrets -n n8n

# Форвардинг портов для локального доступа
kubectl port-forward svc/n8n 8080:80
```

## Следующие шаги

1. **Добавление HTTPS**: Настройка Let's Encrypt через cert-manager
2. **Backup стратегия**: Автоматические резервные копии PostgreSQL
3. **Multi-environment**: Настройка dev/staging/prod окружений
4. **Advanced monitoring**: Интеграция с Azure Monitor
5. **Disaster Recovery**: Настройка репликации в другой регион

## Поддержка

Для получения поддержки:
- Создайте Issue в репозитории
- Проверьте документацию n8n: https://docs.n8n.io/
- Azure AKS документация: https://docs.microsoft.com/azure/aks/

---

*Последнее обновление: 16 сентября 2025*