#!/usr/bin/env sh

set -euo pipefail

log() { echo "[entrypoint] $*"; }
die() { echo "[entrypoint] ERROR: $*" >&2; exit 1; }

# Check if interfaces are present
ip link show "$LAN_IF" >/dev/null 2>&1 || die "interface $LAN_IF not found"
ip link show "$WAN_IF" >/dev/null 2>&1 || die "interface $WAN_IF not found"

# Enable ip forward in the container's network namespace
if [ -w /proc/sys/net/ipv4/ip_forward ]; then
  echo 1 > /proc/sys/net/ipv4/ip_forward
  log "ip_forward enabled for this session ($(cat /proc/sys/net/ipv4/ip_forward))"
else
  die "Cannot write to /proc/sys/net/ipv4/ip_forward, check container privileges / namespace" >&2
fi

# Enable NAT to let other hosts access the upstream network
log "installing NAT rules: $LAN_IF (private) -> $WAN_IF (public)"

iptables -t nat -C POSTROUTING -o "$WAN_IF" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE

iptables -C FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT

iptables -C FORWARD -i "$WAN_IF" -o "$LAN_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i "$WAN_IF" -o "$LAN_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT

# Configure dnsmasq based on environment variables
envsubst < /etc/dnsmasq.conf.template > /etc/dnsmasq.conf

# dnsmasq becomes PID 1
log "Starting dnsmasq"
exec dnsmasq --keep-in-foreground
