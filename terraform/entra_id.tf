# ─────────────────────────────────────────────
# Azure Entra ID – App Registration & SSO
# ─────────────────────────────────────────────

data "azuread_client_config" "current" {}

# Main application registration for the SaaS platform
resource "azuread_application" "college_saas" {
  display_name     = "${local.prefix}-app"
  sign_in_audience = "AzureADMultipleOrgs" # Multi-tenant for SaaS

  web {
    redirect_uris = [
      "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}/auth/callback",
      "https://${azurerm_linux_web_app.student_service.default_hostname}/auth/callback"
    ]

    implicit_grant {
      access_token_issuance_enabled = false
      id_token_issuance_enabled     = true
    }
  }

  api {
    mapped_claims_enabled          = true
    requested_access_token_version = 2

    oauth2_permission_scope {
      admin_consent_description  = "Allow the application to access College SaaS on behalf of the signed-in user"
      admin_consent_display_name = "Access College SaaS"
      enabled                    = true
      id                         = "00000000-0000-0000-0000-000000000001"
      type                       = "User"
      user_consent_description   = "Allow the application to access College SaaS on your behalf"
      user_consent_display_name  = "Access College SaaS"
      value                      = "access_as_user"
    }
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }

    resource_access {
      id   = "37f7f235-527c-4136-accd-4a02d197296e" # openid
      type = "Scope"
    }

    resource_access {
      id   = "64a6cdd6-aab1-4aad-94b8-3cc8405e90d0" # email
      type = "Scope"
    }
  }

  optional_claims {
    access_token {
      name = "tid"
    }
    id_token {
      name = "tid"
    }
    id_token {
      name = "email"
    }
  }

  feature_tags {
    enterprise = true
    gallery    = false
  }
}

# Service Principal
resource "azuread_service_principal" "college_saas" {
  client_id                    = azuread_application.college_saas.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]

  feature_tags {
    enterprise = true
    gallery    = false
  }
}

# Application Secret
resource "azuread_application_password" "college_saas" {
  application_id = azuread_application.college_saas.id
  display_name   = "terraform-managed-secret"
  end_date       = timeadd(timestamp(), "8760h") # 1 year

  lifecycle {
    ignore_changes = [end_date]
  }
}

# ─────────────────────────────────────────────
# App Roles (Student, Faculty, CollegeAdmin)
# ─────────────────────────────────────────────

resource "azuread_application" "college_saas_roles" {
  display_name = "${local.prefix}-roles-app"

  app_role {
    allowed_member_types = ["User"]
    description          = "Student role for accessing student features"
    display_name         = "Student"
    enabled              = true
    id                   = "00000000-0000-0000-0000-000000000010"
    value                = "Student"
  }

  app_role {
    allowed_member_types = ["User"]
    description          = "Faculty role with grading and course management access"
    display_name         = "Faculty"
    enabled              = true
    id                   = "00000000-0000-0000-0000-000000000020"
    value                = "Faculty"
  }

  app_role {
    allowed_member_types = ["User"]
    description          = "College Administrator with full tenant management"
    display_name         = "CollegeAdmin"
    enabled              = true
    id                   = "00000000-0000-0000-0000-000000000030"
    value                = "CollegeAdmin"
  }
}

# ─────────────────────────────────────────────
# Key Vault – Store Entra ID secrets securely
# ─────────────────────────────────────────────

resource "azurerm_key_vault" "main" {
  name                        = "${replace(local.prefix, "-", "")}kv${random_string.suffix.result}"
  resource_group_name         = azurerm_resource_group.main.name
  location                    = var.location
  enabled_for_disk_encryption = true
  tenant_id                   = data.azuread_client_config.current.tenant_id
  soft_delete_retention_days  = 90
  purge_protection_enabled    = true
  sku_name                    = "standard"
  tags                        = local.common_tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    virtual_network_subnet_ids = [
      azurerm_subnet.app_services.id
    ]
  }
}

resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azuread_client_config.current.tenant_id
  object_id    = data.azuread_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
  key_permissions    = ["Get", "List", "Create", "Delete", "Purge", "Recover"]
}

resource "azurerm_key_vault_secret" "entra_client_secret" {
  name         = "entra-client-secret"
  value        = azuread_application_password.college_saas.value
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

resource "azurerm_key_vault_secret" "sql_password" {
  name         = "sql-admin-password"
  value        = var.sql_admin_password
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [azurerm_key_vault_access_policy.terraform]
}
