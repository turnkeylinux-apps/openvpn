#!/bin/bash -eux

fatal() { echo "FATAL [$(basename $0)]: $@" 1>&2; exit 1; }
info() { echo "INFO [$(basename $0)]: $@"; }

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
    addr=$(ipcalc -n $1 | grep Address | awk '{print $2}')
    mask=$(ipcalc -n $1 | grep Netmask | awk '{print $2}')
    echo "$addr $mask"
}
which ipcalc >/dev/null || fatal "ipcalc is not installed"

if [[ "$#" != "3" ]]; then
    usage
fi

key_email=$1
public_address=$2
virtual_subnet=$3


KEY_ORG="${KEY_ORG:-TurnKey Linux}"
KEY_OU="${KEY_OU:-OpenVPN}"
KEY_NAME="${KEY_NAME:-openvpn}"
KEY_COUNTRY="${KEY_COUNTRY:-US}"
KEY_PROVINCE="${KEY_PROVINCE:-CA}"
KEY_CITY="${KEY_CITY:-San Francisco}"
KEY_SIZE="${KEY_SIZE:-2048}"
KEY_EXPIRE="${KEY_EXPIRE:-3650}"
CA_EXPIRE="${CA_EXPIRE:-3650}"

EASY_RSA=/etc/openvpn/easy-rsa
SERVER_CFG=/etc/openvpn/server.conf
SERVER_CCD=/etc/openvpn/server.ccd
SERVER_LOG=/var/log/openvpn/server.log
SERVER_IPP=/var/lib/openvpn/server.ipp

export EASYRSA_PKI="$EASY_RSA/keys"
export EASYRSA_CERT_EXPIRE="$KEY_EXPIRE"
export EASYRSA_DIGEST="sha256"
export EASYRSA_KEY_SIZE=$KEY_SIZE
export EASYRSA_DN=cn_only
export EASYRSA_REQ_CN="must-be-unique"
export EASYRSA_REQ_COUNTRY="$KEY_COUNTRY"
export EASYRSA_REQ_ORG="$KEY_ORG"
export EASYRSA_REQ_OU="$KEY_OU"
export EASYRSA_REQ_NAME="$KEY_NAME"
export EASYRSA_REQ_COUNTRY="$KEY_COUNTRY"
export EASYRSA_REQ_PROVINCE="$KEY_PROVINCE"
export EASYRSA_REQ_CITY="$KEY_CITY"
export EASYRSA_REQ_EMAIL="$key_email"
EASYRSA_NS_SUPPORT="yes"

# remove any files from a previous run to ensure inithook is idempotent
rm -fr "$EASY_RSA/keys/"* "$SERVER_CFG" "$SERVER_CCD"

KEY_DIR="$EASY_RSA/keys"
KEY_CONFIG="$EASY_RSA/openssl-easyrsa.cnf"
OPENSSL="$(which openssl)"
mkdir -p $KEY_DIR

# generate easy-rsa vars file
cat > $EASY_RSA/vars <<EOF
set_var EASY_RSA "$EASY_RSA/easyrsa"
set_var OPENSSL "$(which openssl)"
set_var EASYRSA_PKI "$EASYRSA_PKI"

set_var EASYRSA_KEY_SIZE $KEY_SIZE
set_var EASYRSA_REQ_ORG "$KEY_ORG"
set_var EASYRSA_REQ_EMAIL "$key_email"
set_var EASYRSA_REQ_OU "$KEY_OU"
set_var EASYRSA_REQ_COUNTRY "$KEY_COUNTRY"
set_var EASYRSA_REQ_PROVINCE "$KEY_PROVINCE"
set_var EASYRSA_REQ_CITY "$KEY_CITY"
set_var EASYRSA_REQ_CN "$EASYRSA_REQ_CN"
set_var EASYRSA_DIGEST "$EASYRSA_DIGEST"
set_var EASYRSA_NS_SUPPORT "$EASYRSA_NS_SUPPORT"
set_var EASYRSA_ALGO "rsa"
EOF

# cleanup any prior configurations and initialize
echo "yes" | $EASY_RSA/easyrsa clean-all
rm -f $SERVER_IPP
mkdir -p $(dirname $SERVER_IPP)
mkdir -p $(dirname $SERVER_LOG)
mkdir -p $SERVER_CCD

# generate ca and server keys/certs
export KEY_CN=server
echo "yes" | $EASY_RSA/easyrsa init-pki
$EASY_RSA/easyrsa gen-dh
echo "$EASYRSA_REQ_CN\n" | $EASY_RSA/easyrsa build-ca nopass
echo "server" | $EASY_RSA/easyrsa gen-req server nopass
echo "yes" | $EASY_RSA/easyrsa sign-req server server
openvpn --genkey --secret $KEY_DIR/ta.key

# setup crl jail with empty crl
mkdir -p $KEY_DIR/crl.jail/etc/openvpn/
export KEY_OU=""
export KEY_CN=""
export KEY_NAME=""
$OPENSSL ca -gencrl -config "$KEY_CONFIG" -out "$KEY_DIR/crl.jail/etc/openvpn/crl.pem"
chown nobody:nogroup $KEY_DIR/crl.jail/etc/openvpn/crl.pem
chmod +r $KEY_DIR/crl.jail/etc/openvpn/crl.pem

mkdir -p $KEY_DIR/crl.jail/etc/openvpn
mkdir -p $KEY_DIR/crl.jail/tmp

mv $SERVER_CCD $KEY_DIR/crl.jail/etc/openvpn/
ln -sf $KEY_DIR/crl.jail/etc/openvpn/server.ccd $SERVER_CCD

# generate server configuration
cat > $SERVER_CFG <<EOF
# PUBLIC_ADDRESS: $public_address (used by openvpn-addclient)

port 1194
proto udp
dev tun

cipher AES-256-CBC
auth SHA256

keepalive 10 120

persist-key
persist-tun
user nobody
group nogroup

chroot $KEY_DIR/crl.jail
crl-verify /etc/openvpn/crl.pem

ca $KEY_DIR/ca.crt
dh $KEY_DIR/dh.pem
tls-auth $KEY_DIR/ta.key 0
key $KEY_DIR/private/server.key
cert $KEY_DIR/issued/server.crt

ifconfig-pool-persist $SERVER_IPP
client-config-dir $SERVER_CCD
status $SERVER_LOG
verb 4

# virtual subnet unique for openvpn to draw client addresses from
# the server will be configured with x.x.x.1
# important: must not be used on your network
server $(expand_cidr $virtual_subnet)
EOF
