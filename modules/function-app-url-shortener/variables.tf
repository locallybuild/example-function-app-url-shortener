variable "name_prefix" {
  description = "The prefix used for all resources in this example."
  type        = string
}

variable "location" {
  description = "The region where these resources should be deployed."
  type        = string
}

variable "tags" {
  description = "A mapping of tags which should be applied to each of the resources."
  type        = map(string)
  default     = {}
}

variable "service_plan_sku" {
  description = "App Service plan SKU (Linux), shared by the Function App and the admin site."
  type        = string
  default     = "B1"
}

variable "authority_host" {
  description = "The Microsoft Entra authority App Service signs admins in against. Locally's is https://auth.locally:5677; on Azure it's https://login.microsoftonline.com."
  type        = string
}

variable "admin_principal_ids" {
  description = "Object IDs of the users and groups given the Admin role on the admin site."
  type        = list(string)
}

variable "environment_is_locally" {
  description = "Whether this is being deployed to Locally rather than Azure. The two name an app's SCM site differently."
  type        = bool
  default     = false
}

variable "log_analytics_daily_quota_gb" {
  description = "The most the Log Analytics workspace ingests in a day, in GB. -1 for no limit."
  type        = number
  default     = -1
}
