#!/usr/bin/python3
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
from os.path import exists
import sys
import getopt
from libinithooks import inithooks_cache
from random import randint as r

from libinithooks import is_interactive, warn, info
from libinithooks.dialog_wrapper import Dialog
import subprocess

def fatal(e):
    print("Error:", e, file=sys.stderr)
    sys.exit(1)

def usage(e=None):
    if e:
        print("Error:", e, file=sys.stderr)
    print("Syntax: %s [options]" % sys.argv[0], file=sys.stderr)
    print(__doc__, file=sys.stderr)
    sys.exit(1)

def expand_cidr(cidr):
    network, bitcount = cidr.split('/')
    # turn /<bitcount> into a 32-long bit array
    bits = ('1' * int(bitcount)).ljust(32, '0')
    # split the bit array into 4 bytes
    bytes_list = [
        int(bits[0:8], 2),
        int(bits[8:16], 2),
        int(bits[16:24], 2),
        int(bits[24:32], 2),
    ]
    
    return "{} {}.{}.{}.{}".format(network, *bytes_list)

def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h",
            ['help', 'profile=', 'key-email=', 'public-address=', 'virtual-subnet=',
             'private-subnet='])
    except getopt.GetoptError as e:
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

    tun_exists = exists('/dev/net/tun')
    if not tun_exists:
        if is_interactive:
            dialog.msgbox('Tun device not created', '''
Failed to create `/dev/net/tun` device on boot, this is expected when running inside a non-privileged container.

If you are running on an unprivileged container, you will need to create this device on the host.''')
        else:
            warn('Failed to create `/dev/net/tun` device on boot, this is expected when '
                + 'running inside a non-privileged container. If you are '
                + 'running on an unprivileged container, you will need to '
                + 'create this device on the host.')
    else:
        info('/dev/net/tun created successfully')

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

    inithooks_cache.write('APP_EMAIL', key_email)

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
    subprocess.run([cmd, key_email, public_address, virtual_subnet])

    if profile == "gateway":
        fh = open("/etc/openvpn/server.conf", "a")
        fh.write("# configure clients to route all their traffic through the vpn\n")
        fh.write("push \"redirect-gateway def1 bypass-dhcp\"\n\n")
        fh.close()

    if private_subnet:
        fh = open("/etc/openvpn/server.conf", "a")
        fh.write("# push routes to clients to allow them to reach private subnets\n")
        for _private_subnet in private_subnet.split(',') :
            fh.write("push \"route %s\"\n" % expand_cidr(_private_subnet))
        fh.close()
    subprocess.run(['systemctl', 'start', 'openvpn@server'])

if __name__ == "__main__":
    main()

