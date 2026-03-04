locals {
  prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(var.tags, {
    Environment = var.environment
  })
}

# ─────────────────────────────────────────────
# Resource Groups
# ─────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = "${local.prefix}-rg"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "networking" {
  name     = "${local.prefix}-networking-rg"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "monitoring" {
  name     = "${local.prefix}-monitoring-rg"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "data" {
  name     = "${local.prefix}-data-rg"
  location = var.location
  tags     = local.common_tags
}

# ─────────────────────────────────────────────
# Random suffix for globally unique names
# ─────────────────────────────────────────────

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}
