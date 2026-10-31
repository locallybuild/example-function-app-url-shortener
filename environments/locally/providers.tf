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
  }
}

provider "azuread" {}

provider "azurerm" {
  features {}
}

module "function-app-url-shortener" {
  source = "../../modules/function-app-url-shortener"

  name_prefix = "locally-example-links"
  location    = "berlin"

  environment_is_locally = var.environment_is_locally

  # Admins sign in through Locally's Directory Emulator. The Admin role goes
  # to the seeded "Platform Admins" group: Ada Lovelace, Douglas Engelbart,
  # Edsger Dijkstra and John von Neumann. Anyone else can sign in, but is
  # refused.
  authority_host      = var.authority_host
  admin_principal_ids = ["b2001b4c-ff88-411d-916a-6a2b9cb41d44"]

  tags = {
    ProvisionedVia = "Terraform"
  }
}

# `locally run` sets TF_VAR_environment_is_locally=true, so this is true when
# applied through it.
variable "environment_is_locally" {
  description = "Whether this is being deployed to Locally rather than Azure."
  type        = bool
  default     = false
}

# Locally's App Service Authentication signs users in through 127.0.0.1:5677,
# so the directory's session cookie lives there, and signing out has to go
# there too to end it.
variable "authority_host" {
  description = "The Microsoft Entra authority App Service signs admins in against: Locally's. On Azure, this is https://login.microsoftonline.com."
  type        = string
  default     = "https://127.0.0.1:5677"
}
