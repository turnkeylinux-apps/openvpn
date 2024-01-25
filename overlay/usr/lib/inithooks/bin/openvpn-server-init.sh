#!/bin/bash -eux

fatal() { echo "FATAL [$(basename "$0")]: $*" >&2; exit 1; }
info() { echo "INFO [$(basename "$0")]: $*"; }

usage() {
cat<<EOF
Syntax: $0 key-email public-address virtual-subnet
Initialize OpenVPN easy-rsa, server keys and configuration

Arguments:

    key-email           Email address to use in server key
    public-address      FQDN or IP address of server reachable by clients
    virtual-subnet      CIDR subnet address pool to allocate to clients

Environment:

    KEY_ORG             Default: TurnKey Linux
    KEY_OU              Default: OpenVPN
    KEY_NAME            Default: openvpn
    KEY_COUNTRY         Default: US
    KEY_PROVINCE        Default: CA
    KEY_CITY            Default: San Francisco
    KEY_SIZE            Default: 2048
    KEY_EXPIRE          Default: 3650
    CA_EXPIRE           Default: 3650
EOF
exit 1
}

expand_cidr() {
    addr=$(ipcalc -n "$1" | grep Address | awk '{print $2}')
    mask=$(ipcalc -n "$1" | grep Netmask | awk '{print $2}')
    echo "$addr $mask"
}
which ipcalc >/dev/null || fatal "ipcalc is not installed"

if [[ "$#" != "3" ]]; then
    usage
fi

key_email="$1"
public_address="$2"
virtual_subnet="$3"

KEY_ORG="${KEY_ORG:-TurnKey Linux}"
KEY_OU="${KEY_OU:-OpenVPN}"
KEY_NAME="${KEY_NAME:-openvpn}"
KEY_COUNTRY="${KEY_COUNTRY:-US}"
KEY_PROVINCE="${KEY_PROVINCE:-CA}"
KEY_CITY="${KEY_CITY:-San Francisco}"
KEY_SIZE="${KEY_SIZE:-2048}"
KEY_EXPIRE="${KEY_EXPIRE:-3650}"
CA_EXPIRE="${CA_EXPIRE:-3650}"

EASYRSA='/etc/openvpn/easy-rsa'
SERVER_CFG='/etc/openvpn/server.conf'
SERVER_CCD='/etc/openvpn/server.ccd'
SERVER_LOG='/var/log/openvpn/server.log'
SERVER_IPP='/var/lib/openvpn/server.ipp'

export EASYRSA_PKI="$EASYRSA/keys"
export EASYRSA_CERT_EXPIRE="$KEY_EXPIRE"
export EASYRSA_KEY_SIZE=$KEY_SIZE
export EASYRSA_DN=cn_only
export EASYRSA_REQ_COUNTRY="$KEY_COUNTRY"
export EASYRSA_REQ_ORG="$KEY_ORG"
export EASYRSA_REQ_OU="$KEY_OU"
export EASYRSA_REQ_NAME="$KEY_NAME"
export EASYRSA_REQ_COUNTRY="$KEY_COUNTRY"
export EASYRSA_REQ_PROVINCE="$KEY_PROVINCE"
export EASYRSA_REQ_CITY="$KEY_CITY"
export EASYRSA_REQ_EMAIL="$key_email"

# remove files from a previous run to ensure inithook is idempotent
rm -rf "$EASYRSA_PKI" "$SERVER_CFG" "$SERVER_CCD" "$SERVER_IPP"

KEY_CONFIG="$EASYRSA/openssl-easyrsa.cnf"
OPENSSL="$(which openssl)"
mkdir -p $EASYRSA_PKI

# generate easy-rsa vars file
cat > $EASYRSA_PKI/vars <<EOF
set_var EASYRSA "$EASYRSA"
set_var OPENSSL "$OPENSSL"
set_var EASYRSA_PKI "$EASYRSA_PKI"

set_var EASYRSA_KEY_SIZE $KEY_SIZE
set_var EASYRSA_REQ_ORG "$KEY_ORG"
set_var EASYRSA_REQ_EMAIL "$key_email"
set_var EASYRSA_REQ_OU "$KEY_OU"
set_var EASYRSA_REQ_COUNTRY "$KEY_COUNTRY"
set_var EASYRSA_REQ_PROVINCE "$KEY_PROVINCE"
set_var EASYRSA_REQ_CITY "$KEY_CITY"
EOF

# clean up any prior configurations and initialize
mkdir -p "$(dirname "$SERVER_IPP")"
mkdir -p "$(dirname "$SERVER_LOG")"
mkdir -p "$SERVER_CCD"

# generate ca and server keys/certs
export EASYRSA_BATCH=1
$EASYRSA/easyrsa init-pki soft-reset
$EASYRSA/easyrsa gen-dh
$EASYRSA/easyrsa --req-cn='server' build-ca nopass
$EASYRSA/easyrsa gen-req server nopass
$EASYRSA/easyrsa sign-req server server

# setup crl jail with empty crl
mkdir -p $EASYRSA_PKI/crl.jail/etc/openvpn
mkdir -p $EASYRSA_PKI/crl.jail/tmp

$EASYRSA/easyrsa gen-crl
mv $EASYRSA_PKI/crl.pem $EASYRSA_PKI/crl.jail/etc/openvpn/crl.pem

chown nobody:nogroup $EASYRSA_PKI/crl.jail/etc/openvpn/crl.pem
chmod +r $EASYRSA_PKI/crl.jail/etc/openvpn/crl.pem

mv $SERVER_CCD $EASYRSA_PKI/crl.jail/etc/openvpn/
ln -sf $EASYRSA_PKI/crl.jail/etc/openvpn/server.ccd $SERVER_CCD

openvpn --genkey secret $EASYRSA_PKI/ta.key

# generate server configuration
cat > $SERVER_CFG <<EOF
# PUBLIC_ADDRESS: $public_address (used by openvpn-addclient)

port 1194
proto udp
dev tun

keepalive 10 120

persist-key
persist-tun
user nobody
group nogroup

chroot $EASYRSA_PKI/crl.jail
crl-verify /etc/openvpn/crl.pem

ca $EASYRSA_PKI/ca.crt
dh $EASYRSA_PKI/dh.pem
tls-auth $EASYRSA_PKI/ta.key 0
key $EASYRSA_PKI/private/server.key
cert $EASYRSA_PKI/issued/server.crt

ifconfig-pool-persist $SERVER_IPP
client-config-dir $SERVER_CCD
status $SERVER_LOG
verb 4

# virtual subnet unique for openvpn to draw client addresses from
# the server will be configured with x.x.x.1
# important: must not be used on your network
server $(expand_cidr "$virtual_subnet")
EOF
