terraform {
  required_version = ">= 1.7.0, < 2.0.0"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc10"
    }
  }
}

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_tls_insecure = false

  # Proxmox evaluates the token's scoped ACLs on each API call. The provider's
  # optional precheck would require its broad default role at the cluster root.
  pm_minimum_permission_check = false
}
