variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "college-saas"
}

variable "tenants" {
  description = "List of college tenants"
  type = list(object({
    id   = string
    name = string
  }))
  default = [
    { id = "tenant-a", name = "College A" },
    { id = "tenant-b", name = "College B" },
    { id = "tenant-c", name = "College C" }
  ]
}

variable "sql_admin_username" {
  description = "SQL Server administrator username"
  type        = string
  default     = "sqladmin"
  sensitive   = true
}

variable "sql_admin_password" {
  description = "SQL Server administrator password"
  type        = string
  sensitive   = true
}

variable "apim_publisher_name" {
  description = "API Management publisher name"
  type        = string
  default     = "College SaaS Platform"
}

variable "apim_publisher_email" {
  description = "API Management publisher email"
  type        = string
  default     = "admin@collegesaas.com"
}

variable "app_service_sku" {
  description = "App Service Plan SKU"
  type        = string
  default     = "P2v3"
}

variable "redis_sku" {
  description = "Redis Cache SKU"
  type        = string
  default     = "Standard"
}

variable "redis_family" {
  description = "Redis Cache family"
  type        = string
  default     = "C"
}

variable "redis_capacity" {
  description = "Redis Cache capacity"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "College SaaS Platform"
    ManagedBy   = "Terraform"
    Environment = "prod"
  }
}
