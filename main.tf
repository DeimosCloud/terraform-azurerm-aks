data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

module "ssh-key" {
  source         = "./modules/ssh-key"
  public_ssh_key = var.public_ssh_key == "" ? "" : var.public_ssh_key
}

locals {
  aks_name = "${var.prefix}-aks"
}


resource "azurerm_kubernetes_cluster" "main" {
  name                = local.aks_name
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  dns_prefix          = var.prefix
  private_cluster_enabled = var.private_cluster_enabled


  linux_profile {
    admin_username = var.admin_username

    ssh_key {
      # remove any new lines using the replace interpolation function
      key_data = replace(var.public_ssh_key == "" ? module.ssh-key.public_ssh_key : var.public_ssh_key, "\n", "")
    }
  }

  default_node_pool {
    name            = "nodepool"
    node_count      = var.agents_count
    vm_size         = var.agents_size
    os_disk_size_gb = 50
    vnet_subnet_id  = var.vnet_subnet_id
  }

  service_principal {
    client_id     = var.client_id
    client_secret = var.client_secret
  }
  network_profile {
    network_plugin = var.network_plugin
    network_policy = var.network_policy

  }
  role_based_access_control {
    enabled = true
    azure_active_directory {
      server_app_id     = var.rbac_server_app_id
      server_app_secret = var.rbac_server_app_secret
      client_app_id     = var.rbac_client_app_id
      tenant_id         = var.azure_tenant_id
    }
  }

  dynamic addon_profile {
    for_each = var.enable_log_analytics_workspace ? ["log_analytics"] : []
    content {
      kube_dashboard {
        enabled = var.kube_dashboard_enabled
      }
      oms_agent {
        enabled                    = true
        log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
      }
    }
  }

  tags = var.tags
}


resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_log_analytics_workspace ? 1 : 0
  name                = "${var.prefix}-workspace"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = var.resource_group_name
  sku                 = var.log_analytics_workspace_sku
  retention_in_days   = var.log_retention_in_days

  tags = var.tags
}

resource "azurerm_log_analytics_solution" "main" {
  count                 = var.enable_log_analytics_workspace ? 1 : 0
  solution_name         = "ContainerInsights"
  location              = data.azurerm_resource_group.main.location
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.main[0].id
  workspace_name        = azurerm_log_analytics_workspace.main[0].name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }
}
