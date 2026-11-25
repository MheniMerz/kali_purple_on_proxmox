mock_provider "proxmox" {}

variables {
  proxmox_api_url        = "https://pve.example.test:8006/api2/json"
  proxmox_node           = "pve-test"
  proxmox_pool           = "lab-test"
  proxmox_storage        = "local-lvm"
  vm_template            = "debian-12-cloudinit"
  management_bridge      = "vmbr10"
  lab_bridge             = "vmbr20"
  management_gateway     = "192.0.2.1"
  vm_ssh_public_key      = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA public-test-fixture"
  name_prefix            = "training"
  soc_vm_id              = 6101
  client_vm_id           = 6102
  soc_management_cidr    = "192.0.2.11/24"
  client_management_cidr = "192.0.2.12/24"
  soc_lab_cidr           = "198.51.100.11/24"
  client_lab_cidr        = "198.51.100.12/24"
}

run "plan_two_guests_and_inventory" {
  command = plan

  assert {
    condition = (
      length(proxmox_vm_qemu.lab) == 2 &&
      proxmox_vm_qemu.lab["soc"].vmid == 6101 &&
      proxmox_vm_qemu.lab["client"].vmid == 6102 &&
      alltrue([for vm in proxmox_vm_qemu.lab : vm.full_clone && !vm.force_create && vm.pool == "lab-test"])
    )
    error_message = "Plan exactly two full clones with the lab pool and reserved IDs, without overwriting existing guests."
  }

  assert {
    condition = alltrue([
      for vm in proxmox_vm_qemu.lab :
      length(vm.network) == 2 && alltrue([
        for nic in vm.network : nic.firewall && nic.bridge == (nic.id == 0 ? "vmbr10" : "vmbr20")
      ])
    ])
    error_message = "Each guest must have firewall-enabled management and lab interfaces in the expected order."
  }

  assert {
    condition = (
      proxmox_vm_qemu.lab["soc"].ipconfig0 == "ip=192.0.2.11/24,gw=192.0.2.1" &&
      proxmox_vm_qemu.lab["client"].ipconfig0 == "ip=192.0.2.12/24,gw=192.0.2.1" &&
      proxmox_vm_qemu.lab["soc"].ipconfig1 == "ip=198.51.100.11/24" &&
      proxmox_vm_qemu.lab["client"].ipconfig1 == "ip=198.51.100.12/24"
    )
    error_message = "Cloud-Init must map the IPv4 addresses to the correct NICs and route only via management."
  }

  assert {
    condition = output.ansible_inventory == {
      all = {
        children = {
          soc = {
            hosts = {
              training-kali-purple = {
                ansible_host = "192.0.2.11"
                ansible_user = "ansible"
                lab_address  = "198.51.100.11"
              }
            }
          }
          lab_clients = {
            hosts = {
              training-kali-heliotrope = {
                ansible_host = "192.0.2.12"
                ansible_user = "ansible"
                lab_address  = "198.51.100.12"
              }
            }
          }
        }
      }
    }
    error_message = "The Ansible inventory must contain the correct groups, hostnames, and addresses."
  }
}

run "reject_vm_id_collision" {
  command = plan

  variables {
    client_vm_id = 6101
  }

  expect_failures = [proxmox_vm_qemu.lab]
}

run "reject_overlapping_subnets" {
  command = plan

  variables {
    soc_lab_cidr    = "192.0.2.21/25"
    client_lab_cidr = "192.0.2.22/25"
  }

  expect_failures = [proxmox_vm_qemu.lab]
}

run "reject_cleartext_api_endpoint" {
  command = plan

  variables {
    proxmox_api_url = "http://pve.example.test:8006/api2/json"
  }

  expect_failures = [var.proxmox_api_url]
}

run "plan_opnsense_between_isolated_segments" {
  command = plan

  variables {
    soc_lab_cidr = "203.0.113.11/24"
    opnsense = {
      vm_id       = 6103
      iso         = "local:iso/OPNsense-dvd-amd64.iso"
      soc_bridge  = "vmbr21"
      client_cidr = "198.51.100.1/24"
      soc_cidr    = "203.0.113.1/24"
    }
  }

  assert {
    condition = (
      length(proxmox_vm_qemu.opnsense) == 1 &&
      proxmox_vm_qemu.opnsense[0].vmid == 6103 &&
      length(proxmox_vm_qemu.opnsense[0].network) == 2 &&
      alltrue([
        for nic in proxmox_vm_qemu.opnsense[0].network :
        nic.bridge == (nic.id == 0 ? "vmbr20" : "vmbr21")
      ]) &&
      one([for nic in proxmox_vm_qemu.lab["client"].network : nic.bridge if nic.id == 1]) == "vmbr20" &&
      one([for nic in proxmox_vm_qemu.lab["soc"].network : nic.bridge if nic.id == 1]) == "vmbr21"
    )
    error_message = "Only the firewall must connect to both telemetry bridges."
  }

  assert {
    condition = (
      output.ansible_inventory.all.children.soc.hosts.training-kali-purple.lab_gateway == "203.0.113.1" &&
      output.ansible_inventory.all.children.soc.hosts.training-kali-purple.lab_remote_network == "198.51.100.0/24" &&
      output.ansible_inventory.all.children.lab_clients.hosts.training-kali-heliotrope.lab_gateway == "198.51.100.1" &&
      output.ansible_inventory.all.children.lab_clients.hosts.training-kali-heliotrope.lab_remote_network == "203.0.113.0/24"
    )
    error_message = "Export the firewall next hop and opposite telemetry subnet for both guests."
  }
}

run "reject_firewall_bridge_bypass" {
  command = plan

  variables {
    soc_lab_cidr = "203.0.113.11/24"
    opnsense = {
      vm_id       = 6103
      iso         = "local:iso/OPNsense-dvd-amd64.iso"
      soc_bridge  = "vmbr20"
      client_cidr = "198.51.100.1/24"
      soc_cidr    = "203.0.113.1/24"
    }
  }

  expect_failures = [proxmox_vm_qemu.opnsense]
}
