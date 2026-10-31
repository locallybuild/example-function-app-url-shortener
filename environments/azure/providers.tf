terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    azurerm = {
      source = "hashicorp/azurerm"
      # 5.11 is the first release that accepts .NET 10 for Linux apps.
      version = "~> 5.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # State is kept in a local file by default. For anything shared, keep it in
  # a storage account instead, e.g.:
  #
  # backend "azurerm" {
  #   resource_group_name  = "tfstate"
  #   storage_account_name = "<your state storage account>"
  #   container_name       = "tfstate"
  #   key                  = "url-shortener.tfstate"
  #   use_azuread_auth     = true
  # }
}

# The subscription comes from ARM_SUBSCRIPTION_ID, and the credentials from
# `az login` (or the other ARM_* variables).
provider "azurerm" {
  features {}
}

provider "azuread" {}

# App Service, PostgreSQL and Storage Account names are global across Azure, so
# a random suffix keeps this deployment's from colliding with anyone else's.
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

module "function-app-url-shortener" {
  source = "../../modules/function-app-url-shortener"

  name_prefix = "links-${random_string.suffix.result}"
  location    = var.location

  environment_is_locally = false

  # Admins sign in with Microsoft Entra ID. Whoever runs Terraform is always
  # given the Admin role; admin_principal_ids adds more users or groups.
  authority_host      = "https://login.microsoftonline.com"
  admin_principal_ids = var.admin_principal_ids

  log_analytics_daily_quota_gb = var.log_analytics_daily_quota_gb

  tags = {
    ProvisionedVia = "Terraform"
  }
}

variable "location" {
  description = "The Azure region to deploy to."
  type        = string
  default     = "poland central"
}

variable "admin_principal_ids" {
  description = "Object IDs of users and groups in your tenant to give the Admin role, besides whoever runs Terraform. Assigning it to a group needs Microsoft Entra ID P1."
  type        = list(string)
  default     = []
}

variable "log_analytics_daily_quota_gb" {
  description = "The most the Log Analytics workspace ingests in a day, in GB. Past 5 GB a month, ingestion is billed per GB; -1 removes the limit."
  type        = number
  default     = 0.5
}
