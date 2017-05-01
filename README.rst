OpenVPN™ - Open Source VPN solution
==================================

`OpenVPN™`_ is a full-featured open source SSL VPN solution that
accommodates a wide range of configurations, including remote access,
site-to-site VPNs, Wi-Fi security, and more. OpenVPN™ offers a
cost-effective, lightweight alternative to other VPN technologies that
is well-targeted for the SME and enterprise markets.

This appliance includes all the standard features in `TurnKey Core`_,
and on top of that:

- OpenVPN™ configurations:

    - Initialization hooks to configure common OpenVPN™ deployments
      such as server, gateway and client profiles.
    - All profiles support SSL/TLS certificates for authentication and
      key exchange.
    - Server and gateway deployments include a convenience script to add
      clients, generating all required keys and certificates, as well as
      a unified ovpn profile for clients to easily connect to the VPN.
    - Expiring obfuscated HTTPS urls can be created for clients to
      download their profiles (especially useful with mobile devices
      using a QR code scanner).
    - The server profile supports a private subnet configuration,
      enabling clients to reach servers behind the OpenVPN™ server.
    - The gateway profile configures connecting clients to tunnel all
      their traffic through the VPN.
    - When adding clients in a server or gateway deployment, an optional
      parameter can be given to enable computers on a subnet behind the
      client to connect to the VPN.
    - For added security, OpenVPN™ is configured to drops privilages,
      run in a chroot jail dedicated to CRL, and uses tls-auth for HMAC
      signature verification protecting againsts DoS attacks, port
      flooding, port scanning and buffer overflow vulnerabilities in the
      SSL/TLS implementation.

See the `Usage documentation`_ for further details, including Amazon VPC
notes and cloudformation template.

Note: OpenVPN is a registered trademark of OpenVPN Technologies, Inc.
This software appliance is not support by OpenVPN Technologies, Inc.

Credentials *(passwords set at first boot)*
-------------------------------------------

-  Webmin, SSH: username **root**

.. _OpenVPN™: http://openvpn.net
.. _TurnKey Core: https://www.turnkeylinux.org/core
.. _Usage documentation: https://github.com/turnkeylinux-apps/openvpn/tree/master/docs

