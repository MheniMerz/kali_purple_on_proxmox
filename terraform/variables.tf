variable "proxmox_api_url" {
  description = "HTTPS Proxmox API endpoint with a certificate trusted by the Terraform controller."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^https://[^/?#@[:space:]]+/api2/json$", var.proxmox_api_url))
    error_message = "Use an HTTPS Proxmox API URL ending in /api2/json, without embedded credentials."
  }
}

variable "proxmox_node" {
  description = "Proxmox node containing the Cloud-Init template and the two bridges."
  type        = string
  nullable    = false
}

variable "proxmox_pool" {
  description = "Existing Proxmox resource pool dedicated to this lab."
  type        = string
  nullable    = false

  validation {
    condition     = trimspace(var.proxmox_pool) != ""
    error_message = "Set proxmox_pool to the name of a pre-created lab resource pool."
  }
}

variable "vm_template" {
  description = "Name of a Debian 12 amd64 Cloud-Init template with a scsi0 boot disk and ide2 Cloud-Init drive."
  type        = string
  nullable    = false
}

variable "proxmox_storage" {
  description = "Proxmox storage for the template and cloned VM disks, including their Cloud-Init drives."
  type        = string
  nullable    = false
}

variable "management_bridge" {
  description = "Existing Proxmox bridge for controller-to-guest SSH and restricted update egress."
  type        = string
  nullable    = false
}

variable "lab_bridge" {
  description = "Existing isolated Proxmox bridge for guest-to-guest telemetry."
  type        = string
  nullable    = false
}

variable "management_gateway" {
  description = "Optional IPv4 gateway on the management subnet. The lab subnet has no gateway."
  type        = string
  default     = null

  validation {
    condition     = var.management_gateway == null || can(cidrnetmask("${var.management_gateway}/32"))
    error_message = "Specify management_gateway as an IPv4 address without a prefix length."
  }
}

variable "management_dns_servers" {
  description = "IPv4 DNS resolvers reachable through the management network. An empty list uses Proxmox's Cloud-Init DNS defaults."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for address in var.management_dns_servers : can(cidrnetmask("${address}/32"))])
    error_message = "Each management DNS server must be an IPv4 address without a prefix length."
  }
}

variable "name_prefix" {
  description = "Optional prefix for the Proxmox VM names and Ansible inventory hostnames."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.name_prefix == "" || can(regex("^[a-z0-9]([a-z0-9-]{0,45}[a-z0-9])?$", var.name_prefix))
    error_message = "Use up to 47 lowercase ASCII letters, digits, or hyphens, with no leading or trailing hyphen."
  }
}

variable "vm_user" {
  description = "Unprivileged Cloud-Init username with sudo access for Ansible."
  type        = string
  default     = "ansible"
  nullable    = false

  validation {
    condition     = var.vm_user != "root" && can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.vm_user))
    error_message = "Use a valid non-root Linux account name for vm_user."
  }
}

variable "vm_ssh_public_key" {
  description = "A single OpenSSH public key authorized for vm_user on both guests."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^(ssh-|ecdsa-|sk-)[^[:space:]]+[[:blank:]]+[A-Za-z0-9+/]+={0,2}([[:blank:]]+[^[:cntrl:]]*)?$", trimspace(var.vm_ssh_public_key)))
    error_message = "Provide the contents of a single OpenSSH public key file."
  }
}

variable "soc_vm_id" {
  description = "Unused Proxmox VM ID reserved for Kali Purple."
  type        = number
  nullable    = false

  validation {
    condition     = var.soc_vm_id >= 100 && var.soc_vm_id <= 999999999 && floor(var.soc_vm_id) == var.soc_vm_id
    error_message = "Use an integer Proxmox VM ID between 100 and 999999999."
  }
}

variable "client_vm_id" {
  description = "Unused Proxmox VM ID reserved for Kali Heliotrope."
  type        = number
  nullable    = false

  validation {
    condition     = var.client_vm_id >= 100 && var.client_vm_id <= 999999999 && floor(var.client_vm_id) == var.client_vm_id
    error_message = "Use an integer Proxmox VM ID between 100 and 999999999."
  }
}

variable "soc_management_cidr" {
  description = "Kali Purple IPv4 host address and prefix length on the management bridge."
  type        = string
  nullable    = false

  validation {
    condition     = can(cidrnetmask(var.soc_management_cidr))
    error_message = "Provide soc_management_cidr as an IPv4 address with its prefix length."
  }
}

variable "client_management_cidr" {
  description = "Kali Heliotrope IPv4 host address and prefix length on the management bridge."
  type        = string
  nullable    = false

  validation {
    condition     = can(cidrnetmask(var.client_management_cidr))
    error_message = "Provide client_management_cidr as an IPv4 address with its prefix length."
  }
}

variable "soc_lab_cidr" {
  description = "Kali Purple IPv4 host address and prefix length on the lab bridge."
  type        = string
  nullable    = false

  validation {
    condition     = can(cidrnetmask(var.soc_lab_cidr))
    error_message = "Provide soc_lab_cidr as an IPv4 address with its prefix length."
  }
}

variable "client_lab_cidr" {
  description = "Kali Heliotrope IPv4 host address and prefix length on the lab bridge."
  type        = string
  nullable    = false

  validation {
    condition     = can(cidrnetmask(var.client_lab_cidr))
    error_message = "Provide client_lab_cidr as an IPv4 address with its prefix length."
  }
}

variable "soc_vm_size" {
  description = "Kali Purple VM capacity. Disk size is in GiB."
  type = object({
    cores     = number
    memory_mb = number
    disk_gb   = number
  })
  default = {
    cores     = 4
    memory_mb = 8192
    disk_gb   = 80
  }
  nullable = false

  validation {
    condition     = alltrue([for size in values(var.soc_vm_size) : try(size > 0 && floor(size) == size, false)])
    error_message = "Each SOC VM capacity value must be a positive integer."
  }
}

variable "client_vm_size" {
  description = "Kali Heliotrope VM capacity. Disk size is in GiB."
  type = object({
    cores     = number
    memory_mb = number
    disk_gb   = number
  })
  default = {
    cores     = 1
    memory_mb = 1024
    disk_gb   = 16
  }
  nullable = false

  validation {
    condition     = alltrue([for size in values(var.client_vm_size) : try(size > 0 && floor(size) == size, false)])
    error_message = "Each client VM capacity value must be a positive integer."
  }
}
