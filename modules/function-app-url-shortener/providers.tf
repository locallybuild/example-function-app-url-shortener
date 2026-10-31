terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 5.11 is the first release that accepts .NET 10 for Linux apps.
      version = "~> 5.11"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
