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

# Zone and VNet creation is outside of the scope
# vnet resource considered accessible at `proxmox_sdn_vnet.vnet`

resource "proxmox_oci_image" "hermes" {
  node_name    = "node-1"
  datastore_id = "local"
  reference    = "ghcr.io/richarddorian/hermes:latest"
}

resource "proxmox_virtual_environment_container" "router" {
  node_name = "node-1"

  description = "Hermes: gateway, DHCP and DNS server for vnet${proxmox_sdn_vnet.vnet.tag}"

  unprivileged  = true
  started       = true
  start_on_boot = true
  features {
    # Container doesn't need to create other containers
    nesting = false
  }

  operating_system {
    template_file_id = proxmox_oci_image.hermes.id
  }

  disk {
    datastore_id = "local"
    size         = 1
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 256
  }

  console {
    enabled   = true
    tty_count = 1
    type      = "console"
  }

  initialization {
    hostname = "router-vnet${proxmox_sdn_vnet.vnet.tag}-${each.value.index}"

    entrypoint = "/init /etc/s6-overlay/scripts/wait"
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  network_interface {
    name   = "eth1"
    bridge = proxmox_sdn_vnet.vnet.id
  }

  environment_variables = {
    # Default environment variables need to set again here, Proxmox support for OCI images is poor
    PATH                         = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    S6_BEHAVIOUR_IF_STAGE2_FAILS = "2"

    WAN_IF      = "eth0"
    WAN_ADDRESS = "1.2.3.4" # Public ip address here
    WAN_NETMASK = "255.255.255.0"
    WAN_GATEWAY = "1.2.3.254"

    LAN_IF      = "eth1"
    LAN_ADDRESS = "10.0.${proxmox_sdn_vnet.vnet.tag}.254"

    ENABLE_NAT = "true"

    ENABLE_DNS = "true"
    DOMAIN     = "lan"

    ENABLE_DHCP        = "true"
    DHCP_RANGE_START   = "10.1.${proxmox_sdn_vnet.vnet.tag}.100"
    DHCP_RANGE_END     = "10.1.${proxmox_sdn_vnet.vnet.tag}.200"
    DHCP_NETMASK       = "255.255.255.0"
    DHCP_LEASE_TIME    = "12h"
    DHCP_STATIC_LEASES = "{}"

    ENABLE_WIREGUARD      = "true"
    WIREGUARD_PRIVATE_KEY = "UP89UqFMsgujaLRy6ZOqsGr+XmJUOLvMabec0NX3nV0="
    WIREGUARD_PEERS = jsonencode({
      "10.1.${proxmox_sdn_vnet.vnet.tag}.99" = "ndLNTnQHJjS/pm34i8dqjOEZkAS8iAmy8RNFusYibkA="
    })

    ENABLE_KEEPALIVED = "false"

  }
}
