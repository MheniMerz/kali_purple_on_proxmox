locals {
  inventory_hosts = {
    for role, vm in proxmox_vm_qemu.lab : role => {
      (vm.name) = {
        ansible_host = split("/", local.guests[role].management_cidr)[0]
        ansible_user = var.vm_user
        lab_address  = split("/", local.guests[role].lab_cidr)[0]
      }
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
