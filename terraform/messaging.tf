# ─────────────────────────────────────────────
# Service Bus Namespace
# ─────────────────────────────────────────────

resource "azurerm_servicebus_namespace" "main" {
  name                = "${local.prefix}-sb-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "Premium"
  capacity            = 1
  tags                = local.common_tags

  network_rule_set {
    default_action                = "Deny"
    public_network_access_enabled = false
    trusted_services_allowed      = true

    network_rules {
      subnet_id                            = azurerm_subnet.messaging.id
      ignore_missing_vnet_service_endpoint = false
    }

    network_rules {
      subnet_id                            = azurerm_subnet.app_services.id
      ignore_missing_vnet_service_endpoint = false
    }
  }
}

# ─────────────────────────────────────────────
# Service Bus Queues & Topics
# ─────────────────────────────────────────────

resource "azurerm_servicebus_queue" "notifications" {
  name         = "notifications-queue"
  namespace_id = azurerm_servicebus_namespace.main.id

  lock_duration                = "PT1M"
  max_size_in_megabytes        = 5120
  requires_duplicate_detection = true
  duplicate_detection_history_time_window = "PT10M"
  max_delivery_count           = 10
  dead_lettering_on_message_expiration = true
  default_message_ttl          = "P7D"
  enable_partitioning          = true
}

resource "azurerm_servicebus_queue" "exam_results" {
  name         = "exam-results-queue"
  namespace_id = azurerm_servicebus_namespace.main.id

  lock_duration                = "PT5M"
  max_size_in_megabytes        = 5120
  requires_duplicate_detection = true
  max_delivery_count           = 5
  dead_lettering_on_message_expiration = true
  default_message_ttl          = "P30D"
  enable_partitioning          = true
}

resource "azurerm_servicebus_topic" "tenant_events" {
  name         = "tenant-events-topic"
  namespace_id = azurerm_servicebus_namespace.main.id

  max_size_in_megabytes           = 5120
  requires_duplicate_detection    = true
  duplicate_detection_history_time_window = "PT10M"
  default_message_ttl             = "P7D"
  enable_batched_operations       = true
  enable_partitioning             = true
}

# Subscriptions for tenant events topic
resource "azurerm_servicebus_subscription" "tenant_events_notification" {
  name               = "notification-service-sub"
  topic_id           = azurerm_servicebus_topic.tenant_events.id
  max_delivery_count = 10
  dead_lettering_on_message_expiration = true

  rule {
    name        = "all-events"
    filter_type = "SqlFilter"
    sql_filter  = "EventType IN ('TenantCreated', 'TenantUpdated', 'TenantSuspended')"
  }
}

resource "azurerm_servicebus_subscription" "tenant_events_audit" {
  name               = "audit-service-sub"
  topic_id           = azurerm_servicebus_topic.tenant_events.id
  max_delivery_count = 3
  dead_lettering_on_message_expiration = true
}

# ─────────────────────────────────────────────
# Service Bus Authorization Rules
# ─────────────────────────────────────────────

resource "azurerm_servicebus_namespace_authorization_rule" "app_services" {
  name         = "app-services-rule"
  namespace_id = azurerm_servicebus_namespace.main.id
  listen       = true
  send         = true
  manage       = false
}

# Store connection string in Key Vault
resource "azurerm_key_vault_secret" "servicebus_connection" {
  name         = "servicebus-connection"
  value        = azurerm_servicebus_namespace_authorization_rule.app_services.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# ─────────────────────────────────────────────
# Event Grid Topic
# ─────────────────────────────────────────────

resource "azurerm_eventgrid_topic" "main" {
  name                = "${local.prefix}-egt-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.common_tags

  input_schema = "EventGridSchema"

  inbound_ip_rule {
    ip_mask = azurerm_subnet.app_services.address_prefixes[0]
    action  = "Allow"
  }
}

# Event Grid Subscription – route to Service Bus queue
resource "azurerm_eventgrid_event_subscription" "notifications" {
  name  = "notification-subscription"
  scope = azurerm_eventgrid_topic.main.id

  service_bus_queue_endpoint_id = azurerm_servicebus_queue.notifications.id

  event_delivery_schema = "EventGridSchema"

  included_event_types = [
    "Microsoft.College.ExamSubmitted",
    "Microsoft.College.GradePublished",
    "Microsoft.College.EnrollmentConfirmed"
  ]

  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440
  }

  dead_letter_destination {
    storage_account_id          = azurerm_storage_account.main.id
    storage_blob_container_name = azurerm_storage_container.dead_letter.name
  }
}
