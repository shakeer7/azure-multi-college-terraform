# ─────────────────────────────────────────────
# API Management
# ─────────────────────────────────────────────

resource "azurerm_api_management" "main" {
  name                = "${local.prefix}-apim-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = "Premium_1"
  virtual_network_type = "Internal"
  tags                = local.common_tags

  virtual_network_configuration {
    subnet_id = azurerm_subnet.apim.id
  }

  identity {
    type = "SystemAssigned"
  }

  protocols {
    enable_http2 = true
  }

  security {
    enable_backend_ssl30                     = false
    enable_backend_tls10                     = false
    enable_backend_tls11                     = false
    enable_frontend_ssl30                    = false
    enable_frontend_tls10                    = false
    enable_frontend_tls11                    = false
    tls_ecdhe_ecdsa_with_aes128_cbc_sha_ciphers_enabled = false
    tls_ecdhe_ecdsa_with_aes256_cbc_sha_ciphers_enabled = false
    tls_ecdhe_rsa_with_aes128_cbc_sha_ciphers_enabled   = false
    tls_ecdhe_rsa_with_aes256_cbc_sha_ciphers_enabled   = false
    tls_rsa_with_aes128_cbc_sha256_ciphers_enabled      = false
    tls_rsa_with_aes128_cbc_sha_ciphers_enabled         = false
    tls_rsa_with_aes256_cbc_sha256_ciphers_enabled      = false
    tls_rsa_with_aes256_cbc_sha_ciphers_enabled         = false
  }
}

# ─────────────────────────────────────────────
# APIM APIs
# ─────────────────────────────────────────────

resource "azurerm_api_management_api" "student" {
  name                  = "student-api"
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azurerm_api_management.main.name
  revision              = "1"
  display_name          = "Student Service API"
  path                  = "students"
  protocols             = ["https"]
  subscription_required = true
  api_type              = "http"

  import {
    content_format = "openapi+json-link"
    content_value  = "https://${azurerm_linux_web_app.student_service.default_hostname}/swagger/v1/swagger.json"
  }
}

resource "azurerm_api_management_api" "exam" {
  name                  = "exam-api"
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azurerm_api_management.main.name
  revision              = "1"
  display_name          = "Exam Service API"
  path                  = "exams"
  protocols             = ["https"]
  subscription_required = true
  api_type              = "http"

  import {
    content_format = "openapi+json-link"
    content_value  = "https://${azurerm_linux_web_app.exam_service.default_hostname}/swagger/v1/swagger.json"
  }
}

resource "azurerm_api_management_api" "notification" {
  name                  = "notification-api"
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azurerm_api_management.main.name
  revision              = "1"
  display_name          = "Notification Service API"
  path                  = "notifications"
  protocols             = ["https"]
  subscription_required = true
  api_type              = "http"

  import {
    content_format = "openapi+json-link"
    content_value  = "https://${azurerm_linux_web_app.notification_service.default_hostname}/swagger/v1/swagger.json"
  }
}

# ─────────────────────────────────────────────
# Rate Limiting Policy (Global)
# ─────────────────────────────────────────────

resource "azurerm_api_management_policy" "global" {
  api_management_id = azurerm_api_management.main.id

  xml_content = <<XML
<policies>
  <inbound>
    <!-- Validate JWT from Entra ID -->
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <openid-config url="https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration" />
      <audiences>
        <audience>${azuread_application.college_saas.client_id}</audience>
      </audiences>
    </validate-jwt>

    <!-- Global rate limit: 1000 calls per minute per subscription -->
    <rate-limit calls="1000" renewal-period="60" />

    <!-- Tenant isolation: inject tenant header -->
    <set-header name="X-Tenant-Id" exists-action="override">
      <value>@(context.Subscription.Id)</value>
    </set-header>

    <!-- CORS -->
    <cors allow-credentials="true">
      <allowed-origins>
        <origin>https://${azurerm_cdn_frontdoor_endpoint.main.host_name}</origin>
      </allowed-origins>
      <allowed-methods>
        <method>GET</method>
        <method>POST</method>
        <method>PUT</method>
        <method>DELETE</method>
        <method>PATCH</method>
        <method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>Authorization</header>
        <header>Content-Type</header>
        <header>X-Tenant-Id</header>
      </allowed-headers>
    </cors>
  </inbound>
  <backend>
    <forward-request />
  </backend>
  <outbound>
    <!-- Remove internal headers -->
    <set-header name="X-Powered-By" exists-action="delete" />
    <set-header name="Server" exists-action="delete" />
  </outbound>
  <on-error>
    <return-response>
      <set-status code="@(context.Response.StatusCode)" reason="@(context.Response.StatusReason)" />
      <set-body>@(context.LastError.Message)</set-body>
    </return-response>
  </on-error>
</policies>
XML
}

# ─────────────────────────────────────────────
# Per-tenant Subscriptions
# ─────────────────────────────────────────────

resource "azurerm_api_management_subscription" "tenants" {
  for_each = { for t in var.tenants : t.id => t }

  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "${each.value.name} Subscription"
  state               = "active"
  allow_tracing       = false
}

# ─────────────────────────────────────────────
# APIM Named Values (secrets from Key Vault)
# ─────────────────────────────────────────────

resource "azurerm_api_management_named_value" "client_id" {
  name                = "entra-client-id"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "Entra Client ID"
  value               = azuread_application.college_saas.client_id
  secret              = false
}
