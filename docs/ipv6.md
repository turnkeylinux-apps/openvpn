OpenVPN IPv6 Configuration - OpenVPN v2.6+
==========================================

Inclusion of some updated IPv6 default config are intended for a future TurnKey
release. In the meantime here are some (untested) notes. Please confirm their
validity before rolling out for production. Also please provide feedback if you
try them out.

OpenVPN config
==============

Config file: `/etc/openvpn/server.conf`

Protocol
--------

To set IPv6 as the preferred (UDP) listening address for clients to connect to,
append '6' to the existing `proto udp` config line. I.e. so it looks like this:

```
proto udp6
```

The above will fall back to IPv4 when IPv6 is not available. The current
default (`proto udp`) will do the opposite. I.e. default to IPv4 & fallback to
IPv6 if IPv4 is not available.

IPv6 Tunnel Interface
---------------------

To assign clients IPv6 addresses **within** the tunnel, _add_ these lines:

```
tun-ipv6
push "tun-ipv6"
```

Push IPv6 Routes to Clients
---------------------------

Examples:

Redirect all client IPv6 traffic through the VPN:

```
push "redirect-gateway ipv6"
```

Route public IPv6 traffic through the tunnel:
```
push "route-ipv6 2000::/3"
```

Route the VPN's own IPv6 subnet:
```
push "route-ipv6 fd42:42:42::/112"
```

Redirect _all_ IPv6 traffic through the VPN:
```
push "redirect-gateway ipv6"
```

DNS
---

Push an IPv6-capable DNS server to clients. E.g. Cloudflare DNS:

```
push "dhcp-option DNS 2606:4700:4700::1111"
```

Host server system config
=========================

IPv6 Forwarding
---------------

Enable IPv6 network forwarding:

```
echo 'net.ipv6.ip_forward=1' >> /etc/sysctl.d/40-openvpn.conf
```

And reboot. To check that it has been applied:

```
sysctl net.ipv6.conf.all.forwarding
```

Firewall - ip6tables
--------------------

The default TurnKey firewall rules should already be appropriate for IPv6.
Currently TurnKey still uses iptables config (legacy wrapper around nftables)
via Webmin. You can inspect the rules via Webmin, or `/etc/iptables/rules.v6`.
