# terraform/outputs.tf

# Resource Group
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.n8n.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.n8n.location
}

# AKS Cluster
output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.n8n.name
}

output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.n8n.id
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.n8n.fqdn
}

output "aks_node_resource_group" {
  description = "Auto-generated resource group containing AKS cluster resources"
  value       = azurerm_kubernetes_cluster.n8n.node_resource_group
}

output "aks_identity_principal_id" {
  description = "Principal ID of the AKS cluster managed identity"
  value       = azurerm_kubernetes_cluster.n8n.identity[0].principal_id
}

output "aks_kubelet_identity_object_id" {
  description = "Object ID of the AKS kubelet identity"
  value       = azurerm_kubernetes_cluster.n8n.kubelet_identity[0].object_id
}

# Container Registry
output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.n8n.name
}

output "acr_login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.n8n.login_server
}

# PostgreSQL
output "postgresql_server_name" {
  description = "Name of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.n8n.name
}

output "postgresql_server_fqdn" {
  description = "FQDN of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.n8n.fqdn
}

output "postgresql_database_name" {
  description = "Name of the PostgreSQL database"
  value       = azurerm_postgresql_flexible_server_database.n8n.name
}

# Key Vault
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.n8n.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.n8n.vault_uri
}

# Storage Account
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.n8n.name
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.n8n.primary_connection_string
  sensitive   = true
}

# Monitoring
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.n8n.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.n8n.name
}

output "application_insights_name" {
  description = "Name of Application Insights"
  value       = azurerm_application_insights.n8n.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.n8n.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.n8n.connection_string
  sensitive   = true
}

# Network
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.n8n.name
}

output "aks_subnet_id" {
  description = "ID of the AKS subnet"
  value       = azurerm_subnet.aks.id
}

output "postgres_subnet_id" {
  description = "ID of the PostgreSQL subnet"
  value       = azurerm_subnet.postgres.id
}

# Connection Information
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.n8n.name} --name ${azurerm_kubernetes_cluster.n8n.name}"
}

output "n8n_url" {
  description = "URL to access n8n (after ingress configuration)"
  value       = "https://n8n.demo.example.com"
}

# Summary Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group        = azurerm_resource_group.n8n.name
    aks_cluster          = azurerm_kubernetes_cluster.n8n.name
    postgresql_server    = azurerm_postgresql_flexible_server.n8n.name
    key_vault           = azurerm_key_vault.n8n.name
    container_registry  = azurerm_container_registry.n8n.name
    storage_account     = azurerm_storage_account.n8n.name
    log_analytics      = azurerm_log_analytics_workspace.n8n.name
  }
}