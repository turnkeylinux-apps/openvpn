Site to site (office to Amazon VPC)
-----------------------------------

Amazon Virtual Private Cloud (Amazon VPC) lets you provision a logically
isolated section of the Amazon Web Services (AWS) cloud where you can
launch AWS resources in a virtual network that you define. You have
complete control over your virtual networking environment, including
selection of your own IP address range, creation of subnets, and
configuration of route tables and network gateways.

Creating and configuring a VPC can be a daunting and complex task, so
we've created a cloudformation template (see `contrib`_) which
automatically creates a VPC, internet gateway, public and private
subnets, security groups, launches a TurnKey OpenVPN NAT instance
preseeded with the server profile and configuration, allocates and
associates an elasticip to the OpenVPN instance and configures routing.

Topology
''''''''

::

    office                                                                 vpc
    172.16.0.0/16                                                  10.0.0.0/16
    +--------------+-----------+                  +---------+----------------+
    |              | openvpn   | <=> internet <=> | openvpn |                |
    |              +-----------+                  +---------+                |
    | dmz                      |                  |               subnet_pub |
    | 172.16.0.0/24            |                  |              10.0.0.0/24 |
    +--------------------------+                  +--------------------------+
    | lan                      |                  |               subnet_pvt |
    | 172.16.1.0/24            |                  |              10.0.1.0/24 |
    +--------------------------+                  +--------------------------+

Assumptions and objectives
''''''''''''''''''''''''''

It's assumed the office network (excluding openvpn) is already
configured.

Our objective is to create the VPC, 2 OpenVPN servers (one acting as a
server, the other as a client), and have computers in the office LAN
connect seamlessly and securely via the VPN to servers in the VPC
private subnet.

Step 1: Setup VPC with TurnKey OpenVPN (server)
'''''''''''''''''''''''''''''''''''''''''''''''

The easiest way to setup and configure the VPC including OpenVPN is to
use the cloudformation template (see `contrib`_ for other alternatives).

Note that the TurnKey OpenVPN server profile will need to be configured
with the following:

   - Email address for the OpenVPN server key (e.g., admin@example.com)
   - FQDN of server reachable by clients (e.g., vpn.example.com)
   - CIDR subnet behind server for clients to reach (e.g., 10.0.1.0/24)

The FQDN should be configured to point to the elastic IP of the OpenVPN
server, which is displayed once the CFM stack is created.

Finally, you can launch servers in the private subnet. When doing so,
the security group for the private subnet instances (created during VPC
creation) should be specified.

Step 2: Install TurnKey OpenVPN in Office DMZ (client)
''''''''''''''''''''''''''''''''''''''''''''''''''''''

Once installation is complete, the server will reboot. On first boot it
will prompt for the OpenVPN profile to use, in which case ``client``
should be selected.

Step 3: Create a profile for the Office OpenVPN client
''''''''''''''''''''''''''''''''''''''''''''''''''''''

The office OpenVPN client needs to authenticate to the VPC OpenVPN
server. To do this, create a profile on the server for the client and
restart the service::

    $ ssh root@vpn.example.com

    $ openvpn-addclient -h
      Syntax: openvpn-addclient client-name client-email [private-subnet]
      Generate keys and configuration for a new client

      Arguments:

          client-name         Unique name for client
          client-email        Client email address
          private-subnet      CIDR subnet behind client (optional)

    $ openvpn-addclient office office@example.com 172.16.1.0/24
      INFO: generated /etc/openvpn/easy-rsa/keys/office.ovpn

    $ /etc/init.d/openvpn restart

Step 4: Securely transfer the client profile to the Office OpenVPN client
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

The profile includes secret information, so it should be transfered to
the client via an encrypted channel, such as RSYNC over SSH or SCP::

    SRC: vpn.example.com:/etc/openvpn/easy-rsa/keys/office.ovpn
    DST: dmz-openvpn:/etc/openvpn/office-to-vpc.conf

Note that in the above example the profile extension has changed from
ovpn to conf so the connection will be created at server boot by the
openvpn initscript.

Lastly, start the VPN connection::

    $ /etc/init.d/openvpn start

You should now be able to connect from the office OpenVPN server to
servers in the VPC private subnet, for example::

    $ ssh root@10.0.1.x

For computers on the office LAN to transparently use the VPN connection,
routing needs to be configured to direct 10.0.0.0/24 to the OpenVPN
client.

Step 5: Mobile device (optional)
''''''''''''''''''''''''''''''''

For example sake, lets say that Joe needs access to the servers on the
VPC private subnet when he is on the go via his mobile device.

The first thing to do is create a profile::

    $ ssh root@vpn.example.com

    $ openvpn-client joe-mobile joe@example.com
      INFO: generated /etc/openvpn/easy-rsa/keys/joe-mobile.ovpn

Next, the profile needs to be securely imported into Joe's mobile
device. Unfortunately, it does not support encrypted email, nor does it
have an SD card slot.

For cases like this, TurnKey OpenVPN supports auto-expiring obfuscated
URLs for downloading client profiles via a web browser using HTTPS::

    $ /var/www/openvpn/bin/addprofile joe-mobile
      URL: https://vpn.example.com/profiles/hjsd763hshj762hshj287.../

The obfuscated URLs are long and error prone (not to mention a pain) to
be entered manually. To combat this, the profile URL displays a QR code
that can be scanned by a mobile device.

OK, back to Joe. The administrator could either visit the link himself
and print out the QR code for Joe, or securely send Joe the link to
visit himself.

Once Joe has the QR code (and has installed the OpenVPN app for either
Android or iOS), can scan the QR code with his mobile device and
download the profile which will be automatically imported into the app.

Note that once a profile has been downloaded, it will automatically be
deleted from the OpenVPN web server by an hourly cron job.

Lastly, if Joe misplaces his mobile device the certificate can be
revoked::

    $ source /etc/openvpn/easy-rsa/vars
    $ /etc/openvpn/easy-rsa/revoke-full joe-mobile


.. _contrib: https://github.com/turnkeylinux-apps/openvpn/tree/master/contrib

