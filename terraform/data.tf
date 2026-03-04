# ─────────────────────────────────────────────
# Azure SQL Server
# ─────────────────────────────────────────────

resource "azurerm_mssql_server" "main" {
  name                         = "${local.prefix}-sql-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.data.name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password
  minimum_tls_version          = "1.2"
  tags                         = local.common_tags

  azuread_administrator {
    login_username              = "AzureAD Admin"
    object_id                   = data.azuread_client_config.current.object_id
    azuread_authentication_only = false
  }

  identity {
    type = "SystemAssigned"
  }
}

# SQL Server Firewall – only allow Azure services and app subnet
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "allow-azure-services"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_virtual_network_rule" "app_subnet" {
  name      = "app-subnet-rule"
  server_id = azurerm_mssql_server.main.id
  subnet_id = azurerm_subnet.data.id
}

resource "azurerm_mssql_virtual_network_rule" "app_services_subnet" {
  name      = "app-services-subnet-rule"
  server_id = azurerm_mssql_server.main.id
  subnet_id = azurerm_subnet.app_services.id
}

# SQL Server Auditing
resource "azurerm_mssql_server_extended_auditing_policy" "main" {
  server_id                               = azurerm_mssql_server.main.id
  storage_endpoint                        = azurerm_storage_account.main.primary_blob_endpoint
  storage_account_access_key              = azurerm_storage_account.main.primary_access_key
  storage_account_access_key_is_secondary = false
  retention_in_days                       = 90
  log_monitoring_enabled                  = true
}

# ─────────────────────────────────────────────
# Per-Tenant Databases (Tenant Data Isolation)
# ─────────────────────────────────────────────

resource "azurerm_mssql_database" "shared" {
  name         = "${local.prefix}-shared-db"
  server_id    = azurerm_mssql_server.main.id
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  license_type = "LicenseIncluded"
  sku_name     = "S3"
  tags         = local.common_tags

  threat_detection_policy {
    state                      = "Enabled"
    email_account_admins       = true
    retention_days             = 90
  }

  long_term_retention_policy {
    weekly_retention  = "P4W"
    monthly_retention = "P12M"
    yearly_retention  = "P5Y"
    week_of_year      = 1
  }

  short_term_retention_policy {
    retention_days           = 35
    backup_interval_in_hours = 12
  }
}

# Dedicated database per tenant for strict isolation
resource "azurerm_mssql_database" "tenant" {
  for_each = { for t in var.tenants : t.id => t }

  name         = "${replace(each.key, "-", "")}db"
  server_id    = azurerm_mssql_server.main.id
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  license_type = "LicenseIncluded"
  sku_name     = "S2"
  tags = merge(local.common_tags, {
    TenantId   = each.key
    TenantName = each.value.name
  })

  threat_detection_policy {
    state                = "Enabled"
    email_account_admins = true
    retention_days       = 90
  }

  short_term_retention_policy {
    retention_days           = 35
    backup_interval_in_hours = 12
  }
}

# Store SQL connection in Key Vault
resource "azurerm_key_vault_secret" "sql_connection" {
  name         = "sql-connection"
  value        = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.shared.name};Authentication=Active Directory Default;Encrypt=True;"
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# ─────────────────────────────────────────────
# Azure Blob Storage (Blob Grid)
# ─────────────────────────────────────────────

resource "azurerm_storage_account" "main" {
  name                            = "${replace(local.prefix, "-", "")}sa${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.data.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "GRS"
  min_tls_version                 = "TLS1_2"
  enable_https_traffic_only       = true
  shared_access_key_enabled       = true
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  tags                            = local.common_tags

  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = true
    last_access_time_enabled = true

    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "POST", "PUT"]
      allowed_origins    = ["https://${azurerm_cdn_frontdoor_endpoint.main.host_name}"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices", "Logging", "Metrics"]
    virtual_network_subnet_ids = [azurerm_subnet.data.id, azurerm_subnet.app_services.id]
  }

  identity {
    type = "SystemAssigned"
  }
}

# Storage Containers
resource "azurerm_storage_container" "exam_files" {
  name                  = "exam-files"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "student_documents" {
  name                  = "student-documents"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "dead_letter" {
  name                  = "dead-letter"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Per-tenant blob containers
resource "azurerm_storage_container" "tenant" {
  for_each = { for t in var.tenants : t.id => t }

  name                  = "${each.key}-data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Lifecycle management policy
resource "azurerm_storage_management_policy" "main" {
  storage_account_id = azurerm_storage_account.main.id

  rule {
    name    = "archive-old-exams"
    enabled = true

    filters {
      prefix_match = ["exam-files/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 90
        delete_after_days_since_modification_greater_than          = 2555 # 7 years
      }
    }
  }
}

# ─────────────────────────────────────────────
# Azure Cache for Redis
# ─────────────────────────────────────────────

resource "azurerm_redis_cache" "main" {
  name                          = "${local.prefix}-redis-${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.data.name
  location                      = var.location
  capacity                      = var.redis_capacity
  family                        = var.redis_family
  sku_name                      = var.redis_sku
  enable_non_ssl_port           = false
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  tags                          = local.common_tags

  redis_configuration {
    maxmemory_policy   = "allkeys-lru"
    enable_authentication = true
  }
}

# Private endpoint for Redis
resource "azurerm_private_endpoint" "redis" {
  name                = "${local.prefix}-redis-pe"
  resource_group_name = azurerm_resource_group.data.name
  location            = var.location
  subnet_id           = azurerm_subnet.data.id
  tags                = local.common_tags

  private_service_connection {
    name                           = "redis-psc"
    private_connection_resource_id = azurerm_redis_cache.main.id
    is_manual_connection           = false
    subresource_names              = ["redisCache"]
  }
}

# Store Redis connection in Key Vault
resource "azurerm_key_vault_secret" "redis_connection" {
  name         = "redis-connection"
  value        = azurerm_redis_cache.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [azurerm_key_vault_access_policy.terraform]
}
