# terraform/main.tf

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.70"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.41"
    }
  }

  backend "azurerm" {
  # Конфигурация backend будет передана при инициализации
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {}

# Data sources для получения информации о текущем контексте
data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "n8n" {
  name     = "rg-n8n-${var.environment}"
  location = var.location

  tags = var.common_tags
}

# Virtual Network
resource "azurerm_virtual_network" "n8n" {
  name                = "vnet-n8n-${var.environment}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.n8n.location
  resource_group_name = azurerm_resource_group.n8n.name

  tags = var.common_tags
}

# Subnet для AKS
resource "azurerm_subnet" "aks" {
  name                 = "snet-aks-${var.environment}"
  resource_group_name  = azurerm_resource_group.n8n.name
  virtual_network_name = azurerm_virtual_network.n8n.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Subnet для PostgreSQL
resource "azurerm_subnet" "postgres" {
  name                 = "snet-postgres-${var.environment}"
  resource_group_name  = azurerm_resource_group.n8n.name
  virtual_network_name = azurerm_virtual_network.n8n.name
  address_prefixes     = ["10.0.2.0/24"]
  
  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# Private DNS Zone для PostgreSQL
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.n8n.name

  tags = var.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "pdnszlink-postgres-${var.environment}"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.n8n.id
  resource_group_name   = azurerm_resource_group.n8n.name

  tags = var.common_tags
}

# Azure Container Registry
resource "azurerm_container_registry" "n8n" {
  name                = "acrn8n${var.environment}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.n8n.name
  location            = azurerm_resource_group.n8n.location
  sku                 = "Basic"
  admin_enabled       = false

  tags = var.common_tags
}

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "n8n" {
  name                = "aks-n8n-${var.environment}"
  location            = azurerm_resource_group.n8n.location
  resource_group_name = azurerm_resource_group.n8n.name
  dns_prefix          = "aks-n8n-${var.environment}"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "system"
    node_count          = var.node_count
    vm_size             = var.node_vm_size
    type                = "VirtualMachineScaleSets"
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = var.enable_auto_scaling
    min_count          = var.enable_auto_scaling ? var.min_node_count : null
    max_count          = var.enable_auto_scaling ? var.max_node_count : null
    
    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = "10.1.0.0/16"
    dns_service_ip    = "10.1.0.10"
    outbound_type     = "loadBalancer"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.n8n.id
  }

  azure_policy_enabled = true

  tags = var.common_tags
}

# Role assignment для AKS для доступа к ACR
resource "azurerm_role_assignment" "aks_acr" {
  principal_id                     = azurerm_kubernetes_cluster.n8n.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                           = azurerm_container_registry.n8n.id
  skip_service_principal_aad_check = true
}

# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "n8n" {
  name                   = "psql-n8n-${var.environment}"
  resource_group_name    = azurerm_resource_group.n8n.name
  location              = azurerm_resource_group.n8n.location
  version               = "14"
  delegated_subnet_id   = azurerm_subnet.postgres.id
  private_dns_zone_id   = azurerm_private_dns_zone.postgres.id
  administrator_login   = var.postgres_admin_username
  administrator_password = var.postgres_admin_password
  zone                  = "1"
  storage_mb            = 32768
  sku_name              = "B_Standard_B1ms"
  backup_retention_days = 7

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]

  tags = var.common_tags
}

# PostgreSQL Database
resource "azurerm_postgresql_flexible_server_database" "n8n" {
  name      = "n8n"
  server_id = azurerm_postgresql_flexible_server.n8n.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# Key Vault
resource "azurerm_key_vault" "n8n" {
  name                       = "kv-n8n-${var.environment}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.n8n.location
  resource_group_name        = azurerm_resource_group.n8n.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Create", "Delete", "Get", "List", "Update", "Import", "Backup", "Restore", "Recover"
    ]

    secret_permissions = [
      "Set", "Get", "Delete", "List", "Recover", "Backup", "Restore"
    ]

    certificate_permissions = [
      "Create", "Delete", "Get", "List", "Update", "Import", "ManageContacts", "ManageIssuers"
    ]
  }

  # Access policy для AKS Managed Identity
  access_policy {
    tenant_id = azurerm_kubernetes_cluster.n8n.identity[0].tenant_id
    object_id = azurerm_kubernetes_cluster.n8n.identity[0].principal_id

    secret_permissions = [
      "Get", "List"
    ]
  }

  tags = var.common_tags
}

# Key Vault Secrets
resource "azurerm_key_vault_secret" "postgres_connection_string" {
  name         = "postgres-connection-string"
  value        = "postgresql://${var.postgres_admin_username}:${var.postgres_admin_password}@${azurerm_postgresql_flexible_server.n8n.fqdn}:5432/n8n?sslmode=require"
  key_vault_id = azurerm_key_vault.n8n.id

  tags = var.common_tags
}

resource "azurerm_key_vault_secret" "n8n_encryption_key" {
  name         = "n8n-encryption-key"
  value        = random_password.n8n_encryption_key.result
  key_vault_id = azurerm_key_vault.n8n.id

  tags = var.common_tags
}

resource "random_password" "n8n_encryption_key" {
  length  = 32
  special = true
}

# Log Analytics Workspace для мониторинга
resource "azurerm_log_analytics_workspace" "n8n" {
  name                = "log-n8n-${var.environment}"
  location            = azurerm_resource_group.n8n.location
  resource_group_name = azurerm_resource_group.n8n.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.common_tags
}

# Application Insights
resource "azurerm_application_insights" "n8n" {
  name                = "appi-n8n-${var.environment}"
  location            = azurerm_resource_group.n8n.location
  resource_group_name = azurerm_resource_group.n8n.name
  workspace_id        = azurerm_log_analytics_workspace.n8n.id
  application_type    = "web"

  tags = var.common_tags
}

# Storage Account для n8n файлов
resource "azurerm_storage_account" "n8n" {
  name                     = "san8n${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.n8n.name
  location                 = azurerm_resource_group.n8n.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = var.common_tags
}

resource "azurerm_storage_container" "n8n_files" {
  name                  = "n8n-files"
  storage_account_name  = azurerm_storage_account.n8n.name
  container_access_type = "private"
}