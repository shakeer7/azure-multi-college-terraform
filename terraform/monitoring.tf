# ─────────────────────────────────────────────
# Log Analytics Workspace
# ─────────────────────────────────────────────

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.prefix}-law"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 90
  tags                = local.common_tags
}

# ─────────────────────────────────────────────
# Application Insights
# ─────────────────────────────────────────────

resource "azurerm_application_insights" "main" {
  name                = "${local.prefix}-appinsights"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = var.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  retention_in_days   = 90
  tags                = local.common_tags
}

# ─────────────────────────────────────────────
# Diagnostic Settings for Key Resources
# ─────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "frontdoor" {
  name                       = "${local.prefix}-afd-diag"
  target_resource_id         = azurerm_cdn_frontdoor_profile.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "FrontDoorAccessLog"
  }

  enabled_log {
    category = "FrontDoorWebApplicationFirewallLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "apim" {
  name                       = "${local.prefix}-apim-diag"
  target_resource_id         = azurerm_api_management.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "GatewayLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "sql" {
  name                       = "${local.prefix}-sql-diag"
  target_resource_id         = azurerm_mssql_database.shared.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "SQLInsights"
  }

  enabled_log {
    category = "AutomaticTuning"
  }

  enabled_log {
    category = "QueryStoreRuntimeStatistics"
  }

  enabled_log {
    category = "Errors"
  }

  enabled_log {
    category = "DatabaseWaitStatistics"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "servicebus" {
  name                       = "${local.prefix}-sb-diag"
  target_resource_id         = azurerm_servicebus_namespace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "OperationalLogs"
  }

  enabled_log {
    category = "VNetAndIPFilteringLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "${local.prefix}-kv-diag"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "AuditEvent"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ─────────────────────────────────────────────
# Azure Monitor Alerts
# ─────────────────────────────────────────────

resource "azurerm_monitor_action_group" "critical" {
  name                = "${local.prefix}-critical-ag"
  resource_group_name = azurerm_resource_group.monitoring.name
  short_name          = "critical"
  tags                = local.common_tags

  email_receiver {
    name          = "platform-team"
    email_address = var.apim_publisher_email
    use_common_alert_schema = true
  }
}

# Alert: High HTTP 5xx errors on App Services
resource "azurerm_monitor_metric_alert" "http_5xx" {
  for_each = local.web_apps

  name                = "${local.prefix}-${each.key}-5xx-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [each.value.id]
  description         = "Alert when HTTP 5xx errors exceed threshold"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }
}

# Alert: SQL DTU consumption
resource "azurerm_monitor_metric_alert" "sql_dtu" {
  name                = "${local.prefix}-sql-dtu-alert"
  resource_group_name = azurerm_resource_group.data.name
  scopes              = [azurerm_mssql_database.shared.id]
  description         = "Alert when SQL DTU consumption exceeds 80%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = "dtu_consumption_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }
}

# Alert: Service Bus dead-letter queue messages
resource "azurerm_monitor_metric_alert" "servicebus_dlq" {
  name                = "${local.prefix}-sb-dlq-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_servicebus_namespace.main.id]
  description         = "Alert when Service Bus dead-letter queue has messages"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.ServiceBus/namespaces"
    metric_name      = "DeadletteredMessages"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }
}

# Alert: Redis Cache hit rate
resource "azurerm_monitor_metric_alert" "redis_hit_rate" {
  name                = "${local.prefix}-redis-hitrate-alert"
  resource_group_name = azurerm_resource_group.data.name
  scopes              = [azurerm_redis_cache.main.id]
  description         = "Alert when Redis cache hit rate drops below threshold"
  severity            = 3
  frequency           = "PT15M"
  window_size         = "PT1H"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Cache/Redis"
    metric_name      = "cachehits"
    aggregation      = "Total"
    operator         = "LessThan"
    threshold        = 100
  }

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }
}

# ─────────────────────────────────────────────
# Application Insights Smart Detection
# ─────────────────────────────────────────────

resource "azurerm_application_insights_smart_detection_rule" "slow_requests" {
  name                    = "Slow page load time"
  application_insights_id = azurerm_application_insights.main.id
  enabled                 = true
}

resource "azurerm_application_insights_smart_detection_rule" "failure_anomalies" {
  name                    = "Failure Anomalies"
  application_insights_id = azurerm_application_insights.main.id
  enabled                 = true
}
