variable "opnsense" {
  description = "Enable the isolated OPNsense gateway. Omit to keep the two-VM shared-segment lab."
  type = object({
    vm_id       = number
    iso         = string
    soc_bridge  = string
    client_cidr = string
    soc_cidr    = string
  })
  default = null

  validation {
    condition = var.opnsense == null ? true : (
      var.opnsense.vm_id >= 100 && var.opnsense.vm_id <= 999999999 &&
      floor(var.opnsense.vm_id) == var.opnsense.vm_id &&
      can(regex("^[^:/[:space:]]+:iso/[^/[:space:]]+\\.iso$", var.opnsense.iso)) &&
      trimspace(var.opnsense.soc_bridge) != "" &&
      can(cidrnetmask(var.opnsense.client_cidr)) &&
      can(cidrnetmask(var.opnsense.soc_cidr))
    )
    error_message = "Set a free VM ID, a Proxmox ISO volume ID, an isolated SOC bridge, and IPv4 CIDRs for both OPNsense interfaces."
  }
}

locals {
  opnsense_interfaces = var.opnsense == null ? {} : {
    client = var.opnsense.client_cidr
    soc    = var.opnsense.soc_cidr
  }
}

resource "proxmox_vm_qemu" "opnsense" {
  count = var.opnsense == null ? 0 : 1

  name        = join("-", compact([var.name_prefix, "byzantium"]))
  description = "OPNsense gateway for the isolated Kali Purple lab"
  vmid        = var.opnsense.vm_id
  target_node = var.proxmox_node
  pool        = var.proxmox_pool

  force_create           = false
  define_connection_info = false
  agent                  = 0
  power_state            = "running"
  start_at_node_boot     = true
  bios                   = "seabios"
  scsihw                 = "virtio-scsi-single"
  boot                   = "order=scsi0;ide2"
  memory                 = 4096

  startup_shutdown {
    order            = -1
    shutdown_timeout = -1
    startup_delay    = -1
  }

  cpu {
    cores = 2
  }

  disks {
    scsi {
      scsi0 {
        disk {
          size    = "20G"
          storage = var.proxmox_storage
        }
      }
    }

    ide {
      ide2 {
        cdrom {
          iso = var.opnsense.iso
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = var.lab_bridge
  }

  network {
    id     = 1
    model  = "virtio"
    bridge = var.opnsense.soc_bridge
  }

  lifecycle {
    precondition {
      condition     = !contains([var.soc_vm_id, var.client_vm_id], var.opnsense.vm_id)
      error_message = "Reserve a distinct VM ID for OPNsense."
    }

    precondition {
      condition     = !contains([var.management_bridge, var.lab_bridge], var.opnsense.soc_bridge)
      error_message = "OPNsense needs two isolated telemetry bridges distinct from each other and management."
    }

    precondition {
      condition = (
        cidrhost("${local.lab_subnets.client.network}/${local.lab_subnets.soc.prefix}", 0) != local.lab_subnets.soc.network &&
        cidrhost("${local.lab_subnets.soc.network}/${local.lab_subnets.client.prefix}", 0) != local.lab_subnets.client.network
      )
      error_message = "The client and SOC telemetry subnets must not overlap in routed mode."
    }

    precondition {
      condition = alltrue([
        for role, cidr in local.opnsense_interfaces : try(
          split("/", cidr)[1] == local.lab_subnets[role].prefix &&
          cidrhost(cidr, 0) == local.lab_subnets[role].network &&
          !contains([cidrhost(cidr, 0), cidrhost(cidr, -1), local.lab_subnets[role].address], split("/", cidr)[0]),
          false
        )
      ])
      error_message = "Each OPNsense interface must use a distinct usable address in the matching guest's telemetry subnet and prefix."
    }
  }
}
