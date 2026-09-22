FROM docker.io/library/debian:trixie-slim

RUN apt update && \
  apt install -y --no-install-recommends dnsmasq iptables iproute2 gettext-base && \
  rm -rf /var/lib/apt/lists/*

COPY dnsmasq.conf /etc/dnsmasq.conf.template
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

ENV WAN_IF=eth0 \
    LAN_IF=eth1 \
    CONFIGURE_LAN=true \
    ENABLE_NAT=true \
    LAN_ADDRESS=10.0.0.254 \
    DHCP_RANGE_START=10.0.0.100 \
    DHCP_RANGE_END=10.0.0.200 \
    DHCP_NETMASK=255.255.255.0 \
    DHCP_LEASE_TIME=12h \
    DOMAIN=lan

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
