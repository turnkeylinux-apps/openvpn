#!/usr/bin/python3
"""Initialize OpenVPN easy-rsa, server keys and configuration.

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

# ruff: noqa: C901, CPY001, D103, PLR0912, PLR0915, PTH110, PTH118, PTH120
import getopt
import ipaddress
import re
import subprocess
import sys
from os.path import dirname, exists, join
from random import randint as r
from typing import NoReturn

from libinithooks import info, inithooks_cache, is_interactive, warn
from libinithooks.dialog_wrapper import Dialog

TUN_CONTAINER_MSG = """\
Failed to create `/dev/net/tun` device on boot.

If this server is an unprivileged container, you will need to create the tun \
device on the host system."""

EMAIL_RE = re.compile(
    r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?"
)
HOSTNAME_RE = re.compile(
    r"(?=.{1,253}\Z)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*"
    r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
)


def fatal(e: str) -> NoReturn:
    print("Error:", e, file=sys.stderr)
    sys.exit(1)


def usage(e: str | getopt.GetoptError | None = None) -> None:
    if e:
        print("Error:", e, file=sys.stderr)
    print(f"Syntax: {sys.argv[0]} [options]", file=sys.stderr)
    print(__doc__, file=sys.stderr)
    sys.exit(1)


def validate_email(value: str) -> str:
    if len(value) > 254 or not EMAIL_RE.fullmatch(value):
        fatal("invalid key email address")
    return value


def validate_public_address(value: str) -> str:
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        if not HOSTNAME_RE.fullmatch(value):
            fatal("public address must be an IP address or DNS hostname")
    return value.lower()


def validate_subnet(value: str, label: str) -> str:
    try:
        network = ipaddress.ip_network(value, strict=True)
    except ValueError:
        fatal(f"invalid {label}: {value!r}")
    if network.version != 4:
        fatal(f"{label} must be an IPv4 network")
    return network.with_prefixlen


def expand_cidr(cidr: str) -> str:
    network = ipaddress.IPv4Network(cidr, strict=True)
    return f"{network.network_address} {network.netmask}"


def run_checked(command: list[str], description: str) -> None:
    try:
        subprocess.run(command, check=True)  # noqa: S603
    except (OSError, subprocess.CalledProcessError) as error:
        fatal(f"{description} failed: {error}")


def main() -> None:
    try:
        opts, _args = getopt.gnu_getopt(
            sys.argv[1:],
            "h",
            [
                "help",
                "profile=",
                "key-email=",
                "public-address=",
                "virtual-subnet=",
                "private-subnet=",
            ],
        )
    except getopt.GetoptError as e:
        usage(e)

    profile = ""
    key_email = ""
    public_address = ""
    virtual_subnet = ""
    private_subnet = ""
    for opt, val in opts:
        if opt in ("-h", "--help"):
            usage()
        elif opt == "--profile":
            profile = val
        elif opt == "--key-email":
            key_email = val
        elif opt == "--public-address":
            public_address = val
        elif opt == "--virtual-subnet":
            virtual_subnet = val
        elif opt == "--private-subnet":
            private_subnet = val

    dialog = Dialog("TurnKey Linux - First boot configuration")

    tun_exists = exists("/dev/net/tun")
    if not tun_exists:
        if is_interactive:
            dialog.msgbox("Tun device not created", TUN_CONTAINER_MSG)
        else:
            warn(TUN_CONTAINER_MSG)
    else:
        info("/dev/net/tun created successfully")

    if not profile:
        profile = dialog.menu(
            "OpenVPN Profile",
            "Choose a profile for this server.\n\n"
            "* Gateway: clients will route all traffic through the VPN.",
            [
                ("server", "Accept VPN connections from clients"),
                ("gateway", "Accept VPN connections from clients*"),
                ("client", "Initiate VPN connections to a server"),
            ],
        )

    if profile not in ("server", "gateway", "client"):
        fatal(f"invalid profile: {profile}")

    if profile == "client":
        return

    if not key_email:
        key_email = dialog.get_email(
            "OpenVPN Email",
            "Enter email address for the OpenVPN server key.",
            "admin@example.com",
        )

    if not public_address:
        public_address = dialog.get_input(
            "OpenVPN Public Address",
            "Enter FQDN or IP address of server reachable by clients",
            "vpn.example.com",
        )

    # disable 'pseudo-random generator not suitable for crypto rule [S311]'
    # pseudo-random generator only used for subnet generation
    auto_virtual_subnet = f"10.{r(2, 254)}.{r(2, 254)}.0/24"  # noqa: S311
    if not virtual_subnet:
        virtual_subnet = dialog.get_input(
            "OpenVPN Virtual Subnet",
            "Enter CIDR subnet address pool to allocate to clients. This"
            " server will be configured with x.x.x.1. The CIDR must not be"
            " in-use on your network.",
            auto_virtual_subnet,
        )

    if virtual_subnet.upper() == "AUTO":
        virtual_subnet = auto_virtual_subnet

    if profile == "server" and not private_subnet:
        retcode, private_subnet = dialog.inputbox(
            "OpenVPN Private Subnet",
            "Enter CIDR subnet behind server for clients to reach.",
            "10.0.1.0/24",
            "Apply",
            "Skip",
        )

        # retcode is one of 'ok' ("Apply") or 'cancel' ("Skip")
        if retcode == "cancel":
            private_subnet = ""

    if private_subnet.upper() == "SKIP":
        private_subnet = ""

    key_email = validate_email(key_email)
    public_address = validate_public_address(public_address)
    virtual_subnet = validate_subnet(virtual_subnet, "virtual subnet")
    private_subnets = [
        validate_subnet(item.strip(), "private subnet")
        for item in private_subnet.split(",")
        if item.strip()
    ]
    inithooks_cache.write("APP_EMAIL", key_email)

    cmd = join(dirname(__file__), "openvpn-server-init.sh")
    run_checked(
        [cmd, key_email, public_address, virtual_subnet],
        "OpenVPN server initialization",
    )

    if profile == "gateway":
        with open("/etc/openvpn/server.conf", "a") as fob:
            fob.write(
                "# configure clients to route all their traffic through the"
                " vpn\n",
            )
            fob.write('push "redirect-gateway def1 bypass-dhcp"\n\n')

    if private_subnets:
        with open("/etc/openvpn/server.conf", "a") as fob:
            fob.write(
                "# push routes to clients to allow them to reach private"
                " subnets\n",
            )
            fob.writelines(
                (
                    f'push "route {expand_cidr(subnet)}"\n'
                    for subnet in private_subnets
                ),
            )
    run_checked(
        [
            "/usr/bin/systemctl",
            "restart",
            "openvpn@server",
            "openvpn-masquerade",
        ],
        "OpenVPN services restart",
    )


if __name__ == "__main__":
    main()
