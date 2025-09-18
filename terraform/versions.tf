# terraform/versions.tf

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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}
