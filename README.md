# Hermes

All in one router as a container. This OCI image provides:

- **DNS proxy** (no caching) using `dnsmasq`.
- **DHCP server** using `dnsmasq`.
- **Hostname resolution** to resolve DHCP clients using `dnsmasq`.
- **NAT** to give internet access to the virtual network.
- **High availability** (opt-in) using `keepalived`, floating the LAN address across a pair of nodes via VRRP.

## Motivation

At school, I wanted to run a Proxmox cluster with more virtual machines than I had IP addresses for.
The solution: a virtual network inside the cluster, with a small container acting as its gateway, DHCP
server, and DNS server. That container is Hermes.

## Configuration

Configuration is made through environment variables.

| Name                           | Default         | Description                                                                                                                        |
| ------------------------------ | --------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `WAN_IF`                       | `eth0`          | Network interface connected to the WAN (upstream network).                                                                         |
| `LAN_IF`                       | `eth1`          | Network interface connected to the LAN, served by dnsmasq for DNS/DHCP.                                                            |
| `LAN_ADDRESS`                  | `10.0.0.254`    | IP address of the LAN interface; advertised to DHCP clients as the router and DNS server.                                          |
| `CONFIGURE_LAN`                | `true`          | Whether to bring up `LAN_IF` and assign `LAN_ADDRESS` to it.                                                                       |
| `ENABLE_NAT`                   | `true`          | Whether to enable `ip_forward` and install NAT/forwarding `iptables` rules.                                                        |
| `DHCP_RANGE_START`             | `10.0.0.100`    | First address in the DHCP pool handed out to LAN clients.                                                                          |
| `DHCP_RANGE_END`               | `10.0.0.200`    | Last address in the DHCP pool handed out to LAN clients.                                                                           |
| `DHCP_NETMASK`                 | `255.255.255.0` | Netmask advertised for the DHCP range.                                                                                             |
| `DHCP_LEASE_TIME`              | `12h`           | Duration of DHCP leases.                                                                                                           |
| `DOMAIN`                       | `lan`           | Local domain name used for DNS resolution and hostname expansion of DHCP clients.                                                  |
| `ENABLE_KEEPALIVED`            | `false`         | Whether to run `keepalived`, floating `LAN_ADDRESS` on `LAN_IF` via VRRP instead of assigning it statically.                       |
| `KEEPALIVED_VIRTUAL_ROUTER_ID` | `1`             | VRRP router ID; must match across all nodes of the same HA pair and be unique on the LAN. Only used when `ENABLE_KEEPALIVED=true`. |

### High availability

Setting `ENABLE_KEEPALIVED=true` runs `keepalived` alongside `dnsmasq` and hands it ownership of `LAN_ADDRESS`
on `LAN_IF` instead of assigning it statically. Run two Hermes containers with the same `LAN_ADDRESS` and
`KEEPALIVED_VIRTUAL_ROUTER_ID`, and `keepalived` will float the address to whichever node is reachable,
giving the virtual network a highly available gateway/DHCP/DNS server. Every node starts with the same
priority, so which one currently holds the address is decided automatically by VRRP rather than configured
per node. VRRP advertisements are unauthenticated, so only enable this on a LAN you trust.
