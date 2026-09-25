terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.114.0"
    }
  }
}

provider "proxmox" {
  endpoint = "https://my-proxmox.intra.acme.org:8006/"

  username = "root@pam"
  password = "muSuperSecretPassword"

  insecure = true
}

resource "proxmox_sdn_zone_vxlan" "my-zone" {
  id    = "my-zone"
  peers = ["10.0.0.1", "10.0.0.2", "10.0.0.3"]
}

resource "proxmox_sdn_vnet" "vnet100" {
  id   = "vnet100"
  zone = proxmox_sdn_zone_vxlan.my-zone.id
  tag  = 100
}

# Declaring a subnet is not required, everything is being handled by Hermes

# Import the Hermes image into the node's datastore so it can be used as a container template
resource "proxmox_oci_image" "hermes" {
  node_name    = "node-1"
  datastore_id = "local"
  reference    = "ghcr.io/richarddorian/hermes:latest"
}

resource "proxmox_virtual_environment_container" "router-vnet100" {
  node_name   = "node-1"
  description = "Hermes: gateway, DHCP and DNS server for ${proxmox_sdn_vnet.vnet100.id}"

  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = proxmox_oci_image.hermes.id
  }

  disk {
    datastore_id = "local-lvm"
    size         = 2
  }

  memory {
    dedicated = 256
  }

  initialization {
    hostname = "router-vnet100"

    # eth0: WAN, addressed by the upstream network
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    # eth1: LAN, addressed by Hermes itself
    ip_config {
      ipv4 {
        address = "manual"
      }
    }
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  network_interface {
    name   = "eth1"
    bridge = proxmox_sdn_vnet.vnet100.id
  }

  # Must match the SDN subnet above
  environment_variables = {
    WAN_IF           = "eth0"
    WAN_ADDRESS      = "192.168.1.10/24"
    LAN_IF           = "eth1"
    LAN_ADDRESS      = "10.1.100.254"
    DHCP_RANGE_START = "10.1.100.100"
    DHCP_RANGE_END   = "10.1.100.200"
    DHCP_NETMASK     = "255.255.255.0"
  }
}
