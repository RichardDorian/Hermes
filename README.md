# Hermes

All in one router as a container. This OCI image provides:

- **DNS proxy** (optional, no caching) using `dnsmasq`.
- **DHCP server** (optional) using `dnsmasq`.
- **Hostname resolution** to resolve DHCP clients using `dnsmasq`.
- **NAT** to give internet access to the virtual network.
- **High availability** (opt-in) using `keepalived`, floating the LAN address across a pair of nodes via VRRP.

## Motivation

At school, I wanted to run a Proxmox cluster with more virtual machines than I had IP addresses for.
The solution: a virtual network inside the cluster, with a small container acting as its gateway, DHCP
server, and DNS server. That container is Hermes.

## Configuration

Configuration is made through environment variables.

| Name                           | Default         | Description                                                                                                                                                                               |
| ------------------------------ | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `WAN_IF`                       | `eth0`          | Network interface connected to the WAN (upstream network).                                                                                                                                |
| `WAN_ADDRESS`                  |                 | Required. IP address of the WAN interface, used as the NAT source. Floated by `keepalived` when `ENABLE_KEEPALIVED=true`.                                                                 |
| `WAN_NETMASK`                  | `255.255.255.0` | Netmask of the WAN network.                                                                                                                                                               |
| `WAN_GATEWAY`                  |                 | Required. Upstream gateway, installed as the default route on `WAN_IF`. Follows `WAN_ADDRESS` when `ENABLE_KEEPALIVED=true`.                                                              |
| `LAN_IF`                       | `eth1`          | Network interface connected to the LAN, served by dnsmasq for DNS/DHCP.                                                                                                                   |
| `LAN_ADDRESS`                  | `10.0.0.253`    | IP address of the LAN interface; advertised to DHCP clients as the router and DNS server. Must be unique per node when `ENABLE_KEEPALIVED=true`.                                          |
| `ENABLE_NAT`                   | `true`          | Whether to enable `ip_forward` and install NAT/forwarding `iptables` rules.                                                                                                               |
| `ENABLE_DNS`                   | `true`          | Whether to serve DNS on the LAN. When `false`, DHCP clients are not given a DNS server. `dnsmasq` does not run when both `ENABLE_DNS` and `ENABLE_DHCP` are `false`.                      |
| `ENABLE_DHCP`                  | `true`          | Whether to serve DHCP on the LAN. When `false`, the other `DHCP_*` variables are ignored.                                                                                                 |
| `DHCP_RANGE_START`             | `10.0.0.100`    | First address in the DHCP pool handed out to LAN clients.                                                                                                                                 |
| `DHCP_RANGE_END`               | `10.0.0.200`    | Last address in the DHCP pool handed out to LAN clients.                                                                                                                                  |
| `DHCP_NETMASK`                 | `255.255.255.0` | Netmask advertised for the DHCP range.                                                                                                                                                    |
| `DHCP_LEASE_TIME`              | `12h`           | Duration of DHCP leases.                                                                                                                                                                  |
| `DHCP_STATIC_LEASES`           | `{}`            | JSON object of MAC address to IP address (e.g. `{"bc:24:11:aa:bb:cc": "10.0.0.10"}`) always handed to those clients. The IP must be in the LAN subnet, not necessarily in the DHCP range. |
| `DOMAIN`                       | `lan`           | Local domain name used for DNS resolution and hostname expansion of DHCP clients.                                                                                                         |
| `ENABLE_KEEPALIVED`            | `false`         | Whether to run `keepalived`, floating `KEEPALIVED_VIP` on `LAN_IF` and `WAN_ADDRESS` on `WAN_IF` via VRRP.                                                                                |
| `KEEPALIVED_VIP`               | `10.0.0.254`    | Floating LAN address, advertised to DHCP clients as the router and DNS server instead of `LAN_ADDRESS`. Only used when `ENABLE_KEEPALIVED=true`.                                          |
| `KEEPALIVED_VIRTUAL_ROUTER_ID` | `1`             | VRRP router ID; must match across all nodes of the same HA pair and be unique on the LAN. Only used when `ENABLE_KEEPALIVED=true`.                                                        |
| `ENABLE_WIREGUARD`             | `false`         | Whether to run a WireGuard server giving `WIREGUARD_PEERS` access to the LAN.                                                                                                             |
| `WIREGUARD_PRIVATE_KEY`        |                 | Required when `ENABLE_WIREGUARD=true`. Private key of the WireGuard server (`wg genkey`).                                                                                                 |
| `WIREGUARD_PORT`               | `51820`         | UDP port the WireGuard server listens on.                                                                                                                                                 |
| `WIREGUARD_PEERS`              | `{}`            | JSON object of LAN IP address to public key (e.g. `{"10.0.0.50": "<public key>"}`) of the clients allowed to connect.                                                                     |

### High availability

Setting `ENABLE_KEEPALIVED=true` runs `keepalived` to float `KEEPALIVED_VIP` on `LAN_IF` across nodes. Run two
Hermes containers with the same `KEEPALIVED_VIP`, `WAN_ADDRESS` and `KEEPALIVED_VIRTUAL_ROUTER_ID` but a
different `LAN_ADDRESS` each, and `keepalived` will float the address to whichever node is reachable, giving
the virtual network a highly available gateway/DHCP/DNS server. `WAN_ADDRESS` and the default route via
`WAN_GATEWAY` are floated on `WAN_IF` in the same VRRP instance as `KEEPALIVED_VIP`, so they always move to
the same node. DHCP clients are given `KEEPALIVED_VIP` as their router and DNS server. Every node starts with
the same priority, so which one currently holds the addresses is decided automatically by VRRP rather than
configured per node. VRRP advertisements are unauthenticated, so only enable this on a LAN you trust.

`dnsmasq` only runs on the node currently holding the addresses: `keepalived` starts it when the node becomes
active and stops it otherwise, so only one DHCP server answers at a time. DHCP leases are stored in
`/var/lib/hermes`; mount the same shared storage there on every node so the node taking over knows the leases
already handed out.

`keepalived` holds `KEEPALIVED_VIP` on a dedicated `vrrp.<KEEPALIVED_VIRTUAL_ROUTER_ID>` interface using the
VRRP virtual MAC (`00:00:5e:00:01:<id>`), and `dnsmasq` serves DHCP/DNS on it. Clients therefore see
`KEEPALIVED_VIP` as their DHCP server, so lease renewals reach whichever node is active, and the gateway keeps
the same MAC address across failovers. Hermes also needs a few sysctls in the container:
`net.ipv4.conf.all.arp_ignore=1` and `net.ipv4.conf.all.arp_announce=1`, so ARP requests for `KEEPALIVED_VIP`
are only answered with the virtual MAC, and no strict reverse path filtering
(`net.ipv4.conf.{all,default}.rp_filter` must not be `1`, Hermes uses `2`), since clients reach
`KEEPALIVED_VIP` on the VMAC interface while the route back to them goes through `LAN_IF`. Hermes sets them
when `/proc/sys` is writable, otherwise pass them to the runtime (e.g. `--sysctl` with Docker/Podman).

### WireGuard

Setting `ENABLE_WIREGUARD=true` runs a WireGuard server on `WIREGUARD_PORT`, reachable on `WAN_ADDRESS`. Each
entry of `WIREGUARD_PEERS` gives a client an address on the LAN: Hermes routes it through the tunnel and
answers ARP requests for it, so LAN hosts reach the client as if it was on the LAN. Pick peer addresses in the
LAN subnet but outside the DHCP range, and make sure the host loads the `wireguard` kernel module (containers
cannot load it themselves).

A client configuration looks like:

```ini
[Interface]
PrivateKey = <client private key>
Address = 10.0.0.50/32
DNS = 10.0.0.253

[Peer]
PublicKey = <public key of WIREGUARD_PRIVATE_KEY>
Endpoint = <WAN_ADDRESS>:51820
AllowedIPs = 10.0.0.0/24
```

Use `KEEPALIVED_VIP` as `DNS` with `ENABLE_KEEPALIVED=true`: the WireGuard server then follows the floating
addresses like `dnsmasq`. A new node has no session with the clients, which reconnect within about 15 seconds
of sending traffic after a failover.
