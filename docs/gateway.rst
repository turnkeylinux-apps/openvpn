Gateway: Secure internet access from an untrusted network
---------------------------------------------------------

In certain cases it might be desirable to route all client network
traffic to the internet over an encrypted VPN connection. For these
cases, TurnKey OpenVPN supports the gateway profile.

The gateway profile is very similar to the server profile, except that
instead of configuring a private subnet behind the OpenVPN server which
is pushed to clients to configure routing, the OpenVPN server pushes a
redirect-gateway configuration, causing all IP network traffic to pass
through the OpenVPN gateway (with DHCP as the exception).

Step 1: Launch OpenVPN on Amazon EC2 via the Hub
''''''''''''''''''''''''''''''''''''''''''''''''

OpenVPN launched via the `TurnKey Hub`_ will automatically configure the
gateway profile.

Step 2: Create profiles for clients
'''''''''''''''''''''''''''''''''''

Once the OpenVPN gateway is up and running, clients can be added::

    $ openvpn-addclient client1 client1@example.com
      INFO: generated /etc/openvpn/easy-rsa/keys/client1.ovpn

Step 3: Securely transfer profiles to clients
'''''''''''''''''''''''''''''''''''''''''''''

Refer to steps 4 and 5 in the `Site to Site`_ example.


.. _TurnKey Hub: https://hub.turnkeylinux.org
.. _Site to Site: site-to-site.rst

