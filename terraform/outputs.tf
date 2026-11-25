locals {
  routed_inventory = var.opnsense == null ? {} : {
    for role in keys(local.guests) : role => {
      lab_gateway = split("/", local.opnsense_interfaces[role])[0]
      lab_remote_network = join("/", [
        local.lab_subnets[role == "soc" ? "client" : "soc"].network,
        local.lab_subnets[role == "soc" ? "client" : "soc"].prefix,
      ])
    }
  }

  inventory_hosts = {
    for role, vm in proxmox_vm_qemu.lab : role => {
      (vm.name) = merge({
        ansible_host = split("/", local.guests[role].management_cidr)[0]
        ansible_user = var.vm_user
        lab_address  = split("/", local.guests[role].lab_cidr)[0]
      }, try(local.routed_inventory[role], {}))
    }
  }
}

output "ansible_inventory" {
  description = "Static Ansible inventory. Export with terraform output -json ansible_inventory."
  value = {
    all = {
      children = {
        soc         = { hosts = local.inventory_hosts.soc }
        lab_clients = { hosts = local.inventory_hosts.client }
      }
    }
  }
}

output "opnsense_console" {
  description = "Proxmox console and NIC assignments for the optional OPNsense gateway."
  value = var.opnsense == null ? null : {
    vmid = proxmox_vm_qemu.opnsense[0].vmid
    node = var.proxmox_node
    client = {
      interface = "vtnet0"
      bridge    = var.lab_bridge
      cidr      = var.opnsense.client_cidr
    }
    soc = {
      interface = "vtnet1"
      bridge    = var.opnsense.soc_bridge
      cidr      = var.opnsense.soc_cidr
    }
  }
}
