#!/bin/bash -e

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

[ -n "$KEY_ORG" ] || KEY_ORG="TurnKey Linux"
[ -n "$KEY_OU" ] || KEY_OU="OpenVPN"
[ -n "$KEY_NAME" ] || KEY_NAME="openvpn"
[ -n "$KEY_COUNTRY" ] || KEY_COUNTRY="US"
[ -n "$KEY_PROVINCE" ] || KEY_PROVINCE="CA"
[ -n "$KEY_CITY" ] || KEY_CITY="San Francisco"
[ -n "$KEY_SIZE" ] || KEY_SIZE="2048"
[ -n "$KEY_EXPIRE" ] || KEY_EXPIRE="3650"
[ -n "$CA_EXPIRE" ] || CA_EXPIRE="3650"

EASY_RSA=/etc/openvpn/easy-rsa
SERVER_CFG=/etc/openvpn/server.conf
SERVER_CCD=/etc/openvpn/server.ccd
SERVER_LOG=/var/log/openvpn/server.log
SERVER_IPP=/var/lib/openvpn/server.ipp

# generate easy-rsa vars file
cat > $EASY_RSA/vars <<EOF
export EASY_RSA="$EASY_RSA"
export OPENSSL="openssl"
export PKCS11TOOL="pkcs11-tool"
export GREP="grep"
export KEY_CONFIG=\`\$EASY_RSA/whichopensslcnf \$EASY_RSA\`
export KEY_DIR="\$EASY_RSA/keys"
export PKCS11_MODULE_PATH="dummy"
export PKCS11_PIN="dummy"

export CA_EXPIRE=$CA_EXPIRE
export KEY_EXPIRE=$KEY_EXPIRE
export KEY_SIZE=$KEY_SIZE
export KEY_ORG="$KEY_ORG"
export KEY_EMAIL="$key_email"
export KEY_NAME="$KEY_NAME"
export KEY_OU="$KEY_OU"
export KEY_COUNTRY="$KEY_COUNTRY"
export KEY_PROVINCE="$KEY_PROVINCE"
export KEY_CITY="$KEY_CITY"
export KEY_CN="must-be-unique"
export KEY_ALTNAMES="DNS:must-be-unique"
EOF

# cleanup any prior configurations and initialize
source $EASY_RSA/vars
$EASY_RSA/clean-all
rm -f $SERVER_IPP
mkdir -p $(dirname $SERVER_IPP)
mkdir -p $(dirname $SERVER_LOG)
mkdir -p $SERVER_CCD

# generate ca and server keys/certs
source $EASY_RSA/vars
export KEY_CN=server
$EASY_RSA/build-dh
$EASY_RSA/pkitool --initca
$EASY_RSA/pkitool --server server
openvpn --genkey --secret $KEY_DIR/ta.key

# setup crl jail with empty crl
source $EASY_RSA/vars
mkdir -p $KEY_DIR/crl.jail
export KEY_OU=""
export KEY_CN=""
export KEY_NAME=""
$OPENSSL ca -gencrl -config "$KEY_CONFIG" -out "$KEY_DIR/crl.jail/crl.pem"

mkdir -p $KEY_DIR/crl.jail/etc/openvpn
mkdir -p $KEY_DIR/crl.jail/tmp

mv $SERVER_CCD $KEY_DIR/crl.jail/etc/openvpn/
ln -sf $KEY_DIR/crl.jail/etc/openvpn $SERVER_CCD

# generate server configuration
source $EASY_RSA/vars
cat > $SERVER_CFG <<EOF
# PUBLIC_ADDRESS: $public_address (used by openvpn-addclient)

port 1194
proto udp
dev tun

comp-lzo
keepalive 10 120

persist-key
persist-tun
user nobody
group nogroup

chroot $KEY_DIR/crl.jail
crl-verify crl.pem

ca $KEY_DIR/ca.crt
dh $KEY_DIR/dh$KEY_SIZE.pem
tls-auth $KEY_DIR/ta.key 0
key $KEY_DIR/server.key
cert $KEY_DIR/server.crt

ifconfig-pool-persist $SERVER_IPP
client-config-dir $SERVER_CCD
status $SERVER_LOG
verb 4

# virtual subnet unique for openvpn to draw client addresses from
# the server will be configured with x.x.x.1
# important: must not be used on your network
server $(expand_cidr $virtual_subnet)

EOF

