#!/usr/bin/env sh

set -euo pipefail

log() { echo "[entrypoint] $*"; }
die() { echo "[entrypoint] ERROR: $*" >&2; exit 1; }

# Check if interfaces are present
ip link show "$LAN_IF" >/dev/null 2>&1 || die "interface $LAN_IF not found"
ip link show "$WAN_IF" >/dev/null 2>&1 || die "interface $WAN_IF not found"

if [ "$CONFIGURE_LAN" = "true" ]; then
  log "Configuring LAN"

  # Configure network
  ip link set dev "$LAN_IF" up

  if [ "$ENABLE_KEEPALIVED" = "true" ]; then
    log "ENABLE_KEEPALIVED=true, leaving $LAN_ADDRESS on $LAN_IF to keepalived"
  else
    ip address replace "$LAN_ADDRESS/24" dev "$LAN_IF"
  fi
else
  log "CONFIGURE_LAN=$CONFIGURE_LAN, skipping LAN interface configuration"
fi

if [ "$ENABLE_NAT" = "true" ]; then
  log "Configuring NAT"

  # Enable ip forward in the container's network namespace
  if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    log "ip_forward already enabled"
  elif [ -w /proc/sys/net/ipv4/ip_forward ]; then
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
else
  log "ENABLE_NAT=$ENABLE_NAT, skipping ip_forward and NAT rules"
fi

# Configure dnsmasq based on environment variables
envsubst < /etc/dnsmasq.conf.template > /etc/dnsmasq.conf

if [ "$ENABLE_KEEPALIVED" = "true" ]; then
  # Configure keepalived based on environment variables
  envsubst < /etc/keepalived/keepalived.conf.template > /etc/keepalived/keepalived.conf
fi

# Run dnsmasq (and, if enabled, keepalived) in the foreground, but keep this
# shell as PID 1 so signals (e.g. ctrl-c / SIGINT, or `docker stop` /
# SIGTERM) are trapped and forwarded to them, ensuring the container
# actually exits.
log "Starting dnsmasq"
dnsmasq --keep-in-foreground &
dnsmasq_pid=$!

keepalived_pid=
if [ "$ENABLE_KEEPALIVED" = "true" ]; then
  log "Starting keepalived"
  keepalived --dont-fork --log-console --vrrp &
  keepalived_pid=$!
fi

trap 'log "received signal, stopping"; [ -n "$keepalived_pid" ] && kill -TERM "$keepalived_pid" 2>/dev/null; kill -TERM "$dnsmasq_pid" 2>/dev/null; [ -n "$keepalived_pid" ] && wait "$keepalived_pid" 2>/dev/null; wait "$dnsmasq_pid" 2>/dev/null; exit 0' INT TERM

wait "$dnsmasq_pid"
