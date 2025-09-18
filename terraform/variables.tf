# terraform/variables.tf

variable "environment" {
  description = "Environment name (e.g., demo, dev, prod)"
  type        = string
  default     = "demo"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "West Europe"
}

variable "common_tags" {
  description = "Common tags to be applied to all resources"
  type        = map(string)
  default = {
    Project     = "n8n-demo"
    Environment = "demo"
    ManagedBy   = "terraform"
    Owner       = "DevOps"
  }
}

# AKS Configuration
variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.28.3"
}

variable "node_count" {
  description = "Initial number of nodes in the default node pool"
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_B2s"
}

variable "enable_auto_scaling" {
  description = "Enable auto-scaling for the default node pool"
  type        = bool
  default     = true
}

variable "min_node_count" {
  description = "Minimum number of nodes when auto-scaling is enabled"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes when auto-scaling is enabled"
  type        = number
  default     = 3
}

# PostgreSQL Configuration
variable "postgres_admin_username" {
  description = "Administrator username for PostgreSQL server"
  type        = string
  default     = "n8nadmin"
}

variable "postgres_admin_password" {
  description = "Administrator password for PostgreSQL server"
  type        = string
  sensitive   = true
}

variable "postgres_sku_name" {
  description = "SKU name for PostgreSQL server"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "Storage size in MB for PostgreSQL server"
  type        = number
  default     = 32768
}

variable "postgres_backup_retention_days" {
  description = "Backup retention period in days for PostgreSQL"
  type        = number
  default     = 7
}

# Security Configuration
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict this in production
}

variable "enable_network_policy" {
  description = "Enable network policy for AKS"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "log_analytics_retention_days" {
  description = "Log retention in days for Log Analytics workspace"
  type        = number
  default     = 30
}

# Application Configuration
variable "n8n_image_tag" {
  description = "n8n Docker image tag"
  type        = string
  default     = "1.0.5"
}

variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}