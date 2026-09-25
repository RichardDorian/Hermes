FROM docker.io/library/debian:trixie-slim

RUN apt update && \
  apt install -y --no-install-recommends dnsmasq keepalived iptables iproute2 gettext-base xz-utils && \
  rm -rf /var/lib/apt/lists/*

ADD https://github.com/just-containers/s6-overlay/releases/download/v3.2.3.2/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v3.2.3.2/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz

COPY dnsmasq.conf /etc/dnsmasq.conf.template
COPY s6-overlay /etc/s6-overlay

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

ENTRYPOINT [ "/init" ]
CMD [ "/etc/s6-overlay/scripts/wait" ]
