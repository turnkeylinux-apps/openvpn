#!/usr/bin/python
"""Initialize OpenVPN easy-rsa, server keys and configuration

Options:

    --profile=          Profile to use (server, gateway, client)

Server profile options:

    --key-email=        Email address to use in server key
    --public-address=   FQDN or IP address of server
    --virtual-subnet=   CIDR of virtual subnet (or AUTO)
    --private-subnet=   CIDR of private subnet (or SKIP)

Gateway profile options:

    --key-email=        Email address to use in server key
    --public-address=   FQDN or IP address of server
    --virtual-subnet=   CIDR of virtual subnet (or AUTO)

Note: options not specified but required by profile will be asked interactively
"""

import os
import sys
import getopt
from random import randint as r

import ipcalc

from dialog_wrapper import Dialog
from executil import system

def fatal(e):
    print >> sys.stderr, "Error:", e
    sys.exit(1)

def usage(e=None):
    if e:
        print >> sys.stderr, "Error:", e
    print >> sys.stderr, "Syntax: %s [options]" % sys.argv[0]
    print >> sys.stderr, __doc__
    sys.exit(1)

def expand_cidr(cidr):
    net = ipcalc.Network(cidr)
    return "%s %s" % (net.network(), net.netmask())

def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h",
            ['help', 'profile=', 'key-email=', 'public-address=', 'virtual-subnet=',
             'private-subnet='])
    except getopt.GetoptError, e:
        usage(e)

    profile = ""
    key_email = ""
    public_address = ""
    virtual_subnet = ""
    private_subnet = ""
    redirect_client_gateway = ""
    for opt, val in opts:
        if opt in ('-h', '--help'):
            usage()
        elif opt == '--profile':
            profile = val
        elif opt == '--key-email':
            key_email = val
        elif opt == '--public-address':
            public_address = val
        elif opt == '--virtual-subnet':
            virtual_subnet = val
        elif opt == '--private-subnet':
            private_subnet = val

    dialog = Dialog('TurnKey Linux - First boot configuration')

    if not profile:
        profile = dialog.menu(
            "OpenVPN Profile",
            "Choose a profile for this server.\n\n* Gateway: clients will be configured to route all\n  their traffic through the VPN.",
            [
                ('server', 'Accept VPN connections from clients'),
                ('gateway', 'Accept VPN connections from clients*'),
                ('client', 'Initiate VPN connections to a server')
            ])

    if not profile in ('server', 'gateway', 'client'):
        fatal('invalid profile: %s' % profile)

    if profile == "client":
        return

    if not key_email:
        key_email = dialog.get_email(
            "OpenVPN Email",
            "Enter email address for the OpenVPN server key.",
            "admin@example.com")

    if not public_address:
        public_address = dialog.get_input(
            "OpenVPN Public Address",
            "Enter FQDN or IP address of server reachable by clients",
            "vpn.example.com")

    auto_virtual_subnet = "10.%d.%d.0/24" % (r(2, 254), r(2, 254))
    if not virtual_subnet:
        virtual_subnet = dialog.get_input(
            "OpenVPN Virtual Subnet",
            "Enter CIDR subnet address pool to allocate to clients. This server will be configured with x.x.x.1. The CIDR must not be in-use on your network.",
            auto_virtual_subnet)

    if virtual_subnet.upper() == "AUTO":
        virtual_subnet = auto_virtual_subnet

    if profile == "server":
        if not private_subnet:
            retcode, private_subnet = dialog.inputbox(
                "OpenVPN Private Subnet",
                "Enter CIDR subnet behind server for clients to reach.",
                "10.0.1.0/24", "Apply", "Skip")

    if private_subnet.upper() == "SKIP":
        private_subnet = ""

    cmd = os.path.join(os.path.dirname(__file__), 'openvpn-server-init.sh')
    system(cmd, key_email, public_address, virtual_subnet)

    if profile == "gateway":
        fh = open("/etc/openvpn/server.conf", "a")
        fh.write("# configure clients to route all their traffic through the vpn\n")
        fh.write("push \"redirect-gateway def1 bypass-dhcp\"\n\n")
        fh.close()

    if private_subnet:
        fh = open("/etc/openvpn/server.conf", "a")
        fh.write("# push routes to clients to allow them to reach private subnets\n")
        fh.write("push \"route %s\"\n" % expand_cidr(private_subnet))
        fh.close()

if __name__ == "__main__":
    main()

