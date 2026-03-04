# ─────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────

output "frontdoor_endpoint_url" {
  description = "Azure Front Door endpoint hostname"
  value       = "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}"
}

output "apim_gateway_url" {
  description = "API Management gateway URL"
  value       = azurerm_api_management.main.gateway_url
}

output "apim_developer_portal_url" {
  description = "API Management developer portal URL"
  value       = azurerm_api_management.main.developer_portal_url
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = azurerm_key_vault.main.vault_uri
}

output "sql_server_fqdn" {
  description = "SQL Server fully qualified domain name"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
  sensitive   = true
}

output "service_bus_namespace_name" {
  description = "Service Bus namespace name"
  value       = azurerm_servicebus_namespace.main.name
}

output "application_insights_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "storage_account_name" {
  description = "Blob Storage account name"
  value       = azurerm_storage_account.main.name
}

output "redis_hostname" {
  description = "Redis cache hostname"
  value       = azurerm_redis_cache.main.hostname
  sensitive   = true
}

output "student_service_url" {
  description = "Student Service App URL"
  value       = "https://${azurerm_linux_web_app.student_service.default_hostname}"
}

output "exam_service_url" {
  description = "Exam Service App URL"
  value       = "https://${azurerm_linux_web_app.exam_service.default_hostname}"
}

output "notification_service_url" {
  description = "Notification Service App URL"
  value       = "https://${azurerm_linux_web_app.notification_service.default_hostname}"
}

output "tenant_mgmt_service_url" {
  description = "Tenant Management Service App URL"
  value       = "https://${azurerm_linux_web_app.tenant_mgmt.default_hostname}"
}

output "entra_client_id" {
  description = "Azure Entra ID application client ID"
  value       = azuread_application.college_saas.client_id
}

output "tenant_databases" {
  description = "Per-tenant database names"
  value = {
    for k, v in azurerm_mssql_database.tenant : k => v.name
  }
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  value       = azurerm_log_analytics_workspace.main.id
}
