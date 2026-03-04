# ─────────────────────────────────────────────
# App Service Plan
# ─────────────────────────────────────────────

resource "azurerm_service_plan" "main" {
  name                = "${local.prefix}-asp"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────
# Common App Settings (shared across services)
# ─────────────────────────────────────────────

locals {
  common_app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    ASPNETCORE_ENVIRONMENT              = var.environment == "prod" ? "Production" : "Development"
    AZURE_CLIENT_ID                     = azuread_application.college_saas.client_id
    AZURE_TENANT_ID                     = data.azuread_client_config.current.tenant_id
    AZURE_KEY_VAULT_URI                 = azurerm_key_vault.main.vault_uri
    SERVICEBUS_CONNECTION               = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/servicebus-connection/)"
    REDIS_CONNECTION                    = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/redis-connection/)"
    SQL_CONNECTION                      = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/sql-connection/)"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
  }
}

# ─────────────────────────────────────────────
# Student Service
# ─────────────────────────────────────────────

resource "azurerm_linux_web_app" "student_service" {
  name                      = "${local.prefix}-student-svc-${random_string.suffix.result}"
  resource_group_name       = azurerm_resource_group.main.name
  location                  = var.location
  service_plan_id           = azurerm_service_plan.main.id
  virtual_network_subnet_id = azurerm_subnet.app_services.id
  https_only                = true
  tags                      = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    http2_enabled                           = true
    vnet_route_all_enabled                  = true
    health_check_path                       = "/health"
    health_check_eviction_time_in_min       = 5
    minimum_tls_version                     = "1.2"

    application_stack {
      dotnet_version = "8.0"
    }

    ip_restriction {
      service_tag               = "AzureFrontDoor.Backend"
      ip_address                = null
      virtual_network_subnet_id = null
      action                    = "Allow"
      priority                  = 100
      name                      = "allow-frontdoor"
      headers {
        x_azure_fdid = [azurerm_cdn_frontdoor_profile.main.resource_guid]
      }
    }

    ip_restriction {
      service_tag               = "ApiManagement"
      ip_address                = null
      virtual_network_subnet_id = null
      action                    = "Allow"
      priority                  = 110
      name                      = "allow-apim"
    }

    ip_restriction_default_action = "Deny"
  }

  app_settings = merge(local.common_app_settings, {
    SERVICE_NAME = "StudentService"
  })

  logs {
    application_logs {
      file_system_level = "Warning"
    }
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }
}

# ─────────────────────────────────────────────
# Exam Service
# ─────────────────────────────────────────────

resource "azurerm_linux_web_app" "exam_service" {
  name                      = "${local.prefix}-exam-svc-${random_string.suffix.result}"
  resource_group_name       = azurerm_resource_group.main.name
  location                  = var.location
  service_plan_id           = azurerm_service_plan.main.id
  virtual_network_subnet_id = azurerm_subnet.app_services.id
  https_only                = true
  tags                      = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on              = true
    http2_enabled          = true
    vnet_route_all_enabled = true
    health_check_path      = "/health"
    minimum_tls_version    = "1.2"

    application_stack {
      dotnet_version = "8.0"
    }

    ip_restriction {
      service_tag = "ApiManagement"
      action      = "Allow"
      priority    = 100
      name        = "allow-apim"
    }

    ip_restriction_default_action = "Deny"
  }

  app_settings = merge(local.common_app_settings, {
    SERVICE_NAME = "ExamService"
  })
}

# ─────────────────────────────────────────────
# Notification Service
# ─────────────────────────────────────────────

resource "azurerm_linux_web_app" "notification_service" {
  name                      = "${local.prefix}-notif-svc-${random_string.suffix.result}"
  resource_group_name       = azurerm_resource_group.main.name
  location                  = var.location
  service_plan_id           = azurerm_service_plan.main.id
  virtual_network_subnet_id = azurerm_subnet.app_services.id
  https_only                = true
  tags                      = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on              = true
    http2_enabled          = true
    vnet_route_all_enabled = true
    health_check_path      = "/health"
    minimum_tls_version    = "1.2"

    application_stack {
      dotnet_version = "8.0"
    }

    ip_restriction {
      service_tag = "ServiceBus"
      action      = "Allow"
      priority    = 100
      name        = "allow-servicebus"
    }

    ip_restriction {
      service_tag = "ApiManagement"
      action      = "Allow"
      priority    = 110
      name        = "allow-apim"
    }

    ip_restriction_default_action = "Deny"
  }

  app_settings = merge(local.common_app_settings, {
    SERVICE_NAME             = "NotificationService"
    EVENTGRID_TOPIC_ENDPOINT = azurerm_eventgrid_topic.main.endpoint
  })
}

# ─────────────────────────────────────────────
# Tenant Management Service
# ─────────────────────────────────────────────

resource "azurerm_linux_web_app" "tenant_mgmt" {
  name                      = "${local.prefix}-tenant-svc-${random_string.suffix.result}"
  resource_group_name       = azurerm_resource_group.main.name
  location                  = var.location
  service_plan_id           = azurerm_service_plan.main.id
  virtual_network_subnet_id = azurerm_subnet.app_services.id
  https_only                = true
  tags                      = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on              = true
    http2_enabled          = true
    vnet_route_all_enabled = true
    health_check_path      = "/health"
    minimum_tls_version    = "1.2"

    application_stack {
      dotnet_version = "8.0"
    }

    ip_restriction {
      service_tag = "ApiManagement"
      action      = "Allow"
      priority    = 100
      name        = "allow-apim"
    }

    ip_restriction_default_action = "Deny"
  }

  app_settings = merge(local.common_app_settings, {
    SERVICE_NAME = "TenantManagementService"
  })
}

# ─────────────────────────────────────────────
# Key Vault Access for App Services
# ─────────────────────────────────────────────

locals {
  web_apps = {
    student      = azurerm_linux_web_app.student_service
    exam         = azurerm_linux_web_app.exam_service
    notification = azurerm_linux_web_app.notification_service
    tenant_mgmt  = azurerm_linux_web_app.tenant_mgmt
  }
}

resource "azurerm_key_vault_access_policy" "app_services" {
  for_each = local.web_apps

  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = each.value.identity[0].tenant_id
  object_id    = each.value.identity[0].principal_id

  secret_permissions = ["Get", "List"]

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# ─────────────────────────────────────────────
# Auto-scaling for App Service Plan
# ─────────────────────────────────────────────

resource "azurerm_monitor_autoscale_setting" "app_services" {
  name                = "${local.prefix}-autoscale"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  target_resource_id  = azurerm_service_plan.main.id
  tags                = local.common_tags

  profile {
    name = "default"

    capacity {
      default = 2
      minimum = 2
      maximum = 10
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "2"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}
