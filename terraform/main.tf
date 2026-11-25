locals {
  guests = {
    soc = {
      name            = "kali-purple"
      id              = var.soc_vm_id
      management_cidr = var.soc_management_cidr
      lab_cidr        = var.soc_lab_cidr
      size            = var.soc_vm_size
    }
    client = {
      name            = "kali-heliotrope"
      id              = var.client_vm_id
      management_cidr = var.client_management_cidr
      lab_cidr        = var.client_lab_cidr
      size            = var.client_vm_size
    }
  }

  management_network = cidrhost(var.soc_management_cidr, 0)
  management_prefix  = split("/", var.soc_management_cidr)[1]
  lab_network        = cidrhost(var.soc_lab_cidr, 0)
  lab_prefix         = split("/", var.soc_lab_cidr)[1]
}

resource "proxmox_vm_qemu" "lab" {
  for_each = local.guests

  name        = join("-", compact([var.name_prefix, each.value.name]))
  description = "Managed by Terraform for the Kali Purple SOC lab"
  vmid        = each.value.id
  target_node = var.proxmox_node
  pool        = var.proxmox_pool
  clone       = var.vm_template
  full_clone  = true

  # With an explicit VM ID, false makes the provider reject an existing guest.
  force_create           = false
  define_connection_info = false
  agent                  = 1
  power_state            = "running"
  start_at_node_boot     = true
  skip_ipv6              = true
  bios                   = "seabios"
  scsihw                 = "virtio-scsi-single"
  boot                   = "order=scsi0"
  memory                 = each.value.size.memory_mb

  # The provider reads unset startup and shutdown settings back as -1.
  startup_shutdown {
    order            = -1
    shutdown_timeout = -1
    startup_delay    = -1
  }

  cpu {
    cores = each.value.size.cores
  }

  disks {
    scsi {
      scsi0 {
        disk {
          size    = "${each.value.size.disk_gb}G"
          storage = var.proxmox_storage
        }
      }
    }

    ide {
      ide2 {
        cloudinit {
          storage = var.proxmox_storage
        }
      }
    }
  }

  serial {
    id   = 0
    type = "socket"
  }

  vga {
    type = "serial0"
  }

  network {
    id       = 0
    model    = "virtio"
    bridge   = var.management_bridge
    firewall = true
  }

  network {
    id       = 1
    model    = "virtio"
    bridge   = var.lab_bridge
    firewall = true
  }

  os_type    = "cloud-init"
  ciuser     = var.vm_user
  sshkeys    = trimspace(var.vm_ssh_public_key)
  nameserver = join(" ", var.management_dns_servers)
  ipconfig0  = join(",", compact(["ip=${each.value.management_cidr}", var.management_gateway == null ? "" : "gw=${var.management_gateway}"]))
  ipconfig1  = "ip=${each.value.lab_cidr}"

  lifecycle {
    precondition {
      condition = alltrue([
        for name in [var.proxmox_node, var.proxmox_storage, var.vm_template, var.management_bridge, var.lab_bridge] :
        trimspace(name) != ""
      ])
      error_message = "Set the Proxmox node, storage, Cloud-Init template, and both bridge names."
    }

    precondition {
      condition     = var.management_bridge != var.lab_bridge
      error_message = "The management and lab interfaces must use different Proxmox bridges."
    }

    precondition {
      condition     = var.soc_vm_id != var.client_vm_id
      error_message = "The SOC and client must use different reserved VM IDs."
    }

    precondition {
      condition = alltrue([
        for cidr in [each.value.management_cidr, each.value.lab_cidr] :
        !contains([cidrhost(cidr, 0), cidrhost(cidr, -1)], split("/", cidr)[0])
      ])
      error_message = "Each guest needs a usable host address in both of its network CIDRs."
    }

    precondition {
      condition = (
        var.soc_management_cidr != var.client_management_cidr &&
        var.soc_lab_cidr != var.client_lab_cidr &&
        "${cidrhost(var.client_management_cidr, 0)}/${split("/", var.client_management_cidr)[1]}" == "${local.management_network}/${local.management_prefix}" &&
        "${cidrhost(var.client_lab_cidr, 0)}/${split("/", var.client_lab_cidr)[1]}" == "${local.lab_network}/${local.lab_prefix}"
      )
      error_message = "Each bridge must have one shared subnet and different IP addresses for the two guests."
    }

    precondition {
      condition = (
        cidrhost("${local.lab_network}/${local.management_prefix}", 0) != local.management_network &&
        cidrhost("${local.management_network}/${local.lab_prefix}", 0) != local.lab_network
      )
      error_message = "The management and lab subnets must not overlap."
    }

    precondition {
      condition = var.management_gateway == null ? true : (
        cidrhost("${var.management_gateway}/${local.management_prefix}", 0) == local.management_network &&
        !contains([
          local.management_network,
          cidrhost(var.soc_management_cidr, -1),
          split("/", var.soc_management_cidr)[0],
          split("/", var.client_management_cidr)[0],
        ], var.management_gateway)
      )
      error_message = "The management gateway must be an unused host address in the management subnet."
    }
  }
}
