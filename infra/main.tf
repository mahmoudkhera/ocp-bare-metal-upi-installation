terraform {
  required_providers {
    proxmox = { source = "bpg/proxmox" }
  }
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = var.pve_token
  insecure  = true
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each  = var.vms
  name      = each.key
  vm_id     = each.value.vmid
  node_name = var.pve_node

   cpu {
    sockets = 1
    cores   = each.value.vcpus   # 1 socket x N cores = N vCPUs
    type    = "host"
  }

  memory { dedicated = each.value.memory }

  disk {
    datastore_id = var.datastore
    interface    = "scsi0"
    size         = each.value.disk
  }

  cdrom {
    file_id   = var.iso_file
    interface = "ide3"
  }

  boot_order = ["scsi0", "ide3"]

  network_device {
    bridge      = var.bridge
    mac_address = each.value.mac
    model       = "virtio"
  }

  operating_system { type = "l26" }
  started = false
}

output "mac_addresses" {
  value = { for k, v in proxmox_virtual_environment_vm.node : k => v.mac_addresses[0] }
}

