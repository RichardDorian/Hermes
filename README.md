# Hermes

All in one router as a container. This OCI image provides:

- **DNS proxy** (no caching) using `dnsmasq`.
- **DHCP server** using `dnsmasq`.
- **Hostname resolution** to resolve DHCP clients using `dnsmasq`.

## Configuration

Configuration is made through environment variables.

| Name | Default | Description |
| --- | --- | --- |
| `WAN_IF` | `eth0` | Network interface connected to the WAN (upstream network). |
| `LAN_IF` | `eth1` | Network interface connected to the LAN, served by dnsmasq for DNS/DHCP. |
| `LAN_ADDRESS` | `10.0.0.254` | IP address of the LAN interface; advertised to DHCP clients as the router and DNS server. |
| `DHCP_RANGE_START` | `10.0.0.100` | First address in the DHCP pool handed out to LAN clients. |
| `DHCP_RANGE_END` | `10.0.0.200` | Last address in the DHCP pool handed out to LAN clients. |
| `DHCP_NETMASK` | `255.255.255.0` | Netmask advertised for the DHCP range. |
| `DHCP_LEASE_TIME` | `12h` | Duration of DHCP leases. |
| `DOMAIN` | `lan` | Local domain name used for DNS resolution and hostname expansion of DHCP clients. |
