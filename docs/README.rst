Overview
--------

TurnKey OpenVPN supports a wide range of use cases out of the box. The
most common use cases are site-to-site and secure internet access from
an untrusted network.

The appliance includes an initialization hook which supports 3 profiles:

* server: Accepts VPN connections from clients and optionally configures
  a private subnet behind the OpenVPN enabling client access.

* gateway: Accepts VPN connections from clients and automatically
  configures connecting clients to route all their traffic through the
  VPN.

* client: Initiates VPN connections to an OpenVPN server.

For server and gateway deployments, a convenience script is included to
add clients, generating all required keys and certificates, as well as a
unified ovpn profile for clients to easily connect to the VPN.

Additionally, expiring obfuscated HTTPS links can be created for clients
to download their profiles (especially useful with mobile devices using
a QR code scanner).

Potential issues caused by timezone mismatch
--------------------------------------------

Some VPN client applications expect certificate timestamps to be in local
time. However, by default, TurnKey servers use UTC time.

That can lead to the creation of certificates, which according to local
time, are not yet valid. Under these circumstance, connection will fail.

To avoid that, please set the timezone for your TurnKey OpenVPN server
prior to further configuration. To do that via the commandline::

    dpkg-reconfigure tzdata

For further info re setting timezone, please see this_ TurnKey Blog post.

Documentation
-------------

* `Site to Site`_ (office to Amazon VPC - covers both server and client)
* `Gateway`_ (secure internet access)

.. _Site to Site: site-to-site.rst
.. _Gateway: gateway.rst
.. _this: https://www.turnkeylinux.org/blog/configuring-timezone
