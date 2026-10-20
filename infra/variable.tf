variable "pve_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token in the form user@realm!tokenid=secret (for example root@pam!terraform=xxxx)"
  default="root@pam!terraform=xxxx"
}

variable "pve_endpoint" {
  type        = string
  default     = "https://100.88.37.54:8006/"
  description = "URL of the Proxmox API. Must be https and include port 8006."
}

variable "pve_node" {
  type        = string
  description = "Name of the Proxmox node that will host the VMs, as shown in the UI tree or by running 'hostname' on the node."
  default     = "mousa"
}

variable "bridge" {
  type        = string
  default     = "vmbr1"
  description = "Proxmox Linux bridge the VM NICs attach to. It must be the bridge connected to the 192.168.10.0/24 network."
}

variable "iso_file" {
  type        = string
  default     = "local:iso/rhcos-live.x86_64.iso"
  description = "RHCOS live ISO to boot for installation, in the form <storage>:iso/<filename>. The file must already be uploaded to that storage."
}

variable "datastore" {
  type        = string
  default     = "hdd_1"
  description = "Proxmox storage where the VM disks are created."
}

variable "vms" {
  type = map(object({
    vmid   = number
    vcpus  = number
    memory = number
    disk   = number
    mac    = string
  }))
  description = "VMs to create, keyed by VM name (also used as the hostname label). Each entry sets the fields below."
}