#!/bin/bash
set -Eeuo pipefail
umask 077

trap 'status=$?; printf "FAIL: tests/v19.sh line %s: %s (status %s)\\n" "$LINENO" "$BASH_COMMAND" "$status" >&2' ERR

result=${TKL_TEST_RESULT:?TKL_TEST_RESULT is required}
client_name=tklv19client$$
namespace=tklvpn$$
host_veth=tvh$$
client_veth=tvc$$
client_profile=/run/tkl-openvpn-client.$$.ovpn
client_log=/run/tkl-openvpn-client.$$.log
client_pid=/run/tkl-openvpn-client.$$.pid
response=/run/tkl-openvpn-response.$$
policy=/run/tkl-openvpn-policy.$$
private_subnet=198.51.100.0/24
published_profile=
client_created=false

cleanup() {
    local status=$?
    set +e
    if [[ -s $client_pid ]]; then
        kill "$(cat "$client_pid")" >/dev/null 2>&1
    fi
    ip netns delete "$namespace" >/dev/null 2>&1
    if [[ $client_created == true &&
          -e /etc/openvpn/easy-rsa/keys/$client_name.ovpn ]]; then
        openvpn-removeclient "$client_name" >/dev/null 2>&1
    fi
    rm -f -- "$client_profile" "$client_log" "$client_pid" \
        "$response" "$policy"
    exit "$status"
}
trap cleanup EXIT

wait_for_client_tunnel() {
    local attempts=60
    while ((attempts > 0)); do
        if ip netns exec "$namespace" ip -4 -o address show dev tun0 \
                >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        ((attempts -= 1))
    done
    echo "OpenVPN client did not establish tun0" >&2
    sed -n '1,200p' "$client_log" >&2 || true
    return 1
}

count_nat_rules() {
    local interface=$1

    iptables-save -t nat | awk -v interface="$interface" '
        index($0, "-o " interface " ") &&
                $0 ~ /--comment "?turnkey-openvpn"?([[:space:]]|$)/ {
            count += 1
        }
        END { print count + 0 }
    '
}

profile_diagnostics() {
    local phase=$1
    local path
    local url

    {
        echo "--- profile diagnostics: $phase ---"
        lighttpd -p -f /etc/lighttpd/lighttpd.conf 2>&1 |
            grep -E 'server\.document-root|server\.errorlog|accesslog\.filename|index-file\.names|\$SERVER\["socket"\]|ssl\.engine' || true
        for path in \
                /var/www/openvpn/htdocs \
                /var/www/openvpn/htdocs/profiles \
                "$published_profile" \
                "$published_profile/index.html" \
                "$published_profile/$client_name.ovpn"; do
            echo "--- path: $path ---"
            namei -l "$path" || true
            readlink -e "$path" || true
            stat -Lc 'mode=%a owner=%U group=%G type=%F size=%s path=%n' \
                "$path" || true
        done
        for path in \
                /var/www/openvpn/logs/access.log \
                /var/log/lighttpd/error.log; do
            echo "--- log: $path ---"
            tail -n 80 "$path" || true
        done
        journalctl -u lighttpd.service -b --no-pager -n 80 || true
        for url in \
                /profiles/ \
                "$profile_path" \
                "${profile_path}index.html" \
                "${profile_path}${client_name}.ovpn"; do
            curl --insecure --silent --show-error --noproxy '*' \
                --header 'Host: localhost' --output /dev/null \
                --write-out "probe=$url status=%{http_code} effective=%{url_effective}\\n" \
                "https://127.0.0.1$url" || true
        done
        echo "--- end profile diagnostics: $phase ---"
    } >&2
}

# The harness completes firstboot with AUTO_RUN=true.  That inherited headless
# path intentionally leaves the initialization fence active, so finish the
# test-only transition to a post-initialization appliance before probing an
# inbound address.  Otherwise PREROUTING redirects HTTPS to simplehttpd instead
# of the appliance Lighttpd service.
if systemctl --quiet is-active turnkey-init-fence.service; then
    echo "INFO: stopping harness AUTO_RUN initialization fence" >&2
    iptables-save -t nat |
        grep -E -- '--dport (80|443).*--to-ports? (60080|60443)' >&2 || true
    systemctl stop turnkey-init-fence.service
fi
! systemctl --quiet is-active turnkey-init-fence.service

systemctl --quiet is-active openvpn@server.service \
    openvpn-masquerade.service lighttpd.service multi-user.target
systemctl --quiet is-enabled openvpn@server.service \
    openvpn-masquerade.service
lighttpd -tt -f /etc/lighttpd/lighttpd.conf
grep -Fq 'server.document-root := "/var/www/openvpn/htdocs/"' \
    /etc/lighttpd/conf-enabled/50-tklcp.conf
! grep -Eq 'ssl\.engine|include[[:space:]]+"ssl-params\.conf"|\$SERVER\["socket"\]' \
    /etc/lighttpd/conf-enabled/50-tklcp.conf
grep -q '\[40openvpn\].*successfully completed' /var/log/inithooks.log
test -c /dev/net/tun
test -s /etc/openvpn/server.conf
test -s /etc/openvpn/easy-rsa/keys/ca.crt
test -s /etc/openvpn/easy-rsa/keys/private/server.key
test "$(stat -c %a:%U:%G /var/www/openvpn/htdocs/profiles)" = \
    750:www-data:www-data
grep -Fxq 'data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305' \
    /etc/openvpn/server.conf
grep -Fxq 'topology subnet' /etc/openvpn/server.conf
grep -Fxq 'explicit-exit-notify 1' /etc/openvpn/server.conf
grep -Fxq 'push "redirect-gateway def1 bypass-dhcp"' \
    /etc/openvpn/server.conf

# Administrator-provided config values must fail closed before replacing PKI.
server_config_sha=$(sha256sum /etc/openvpn/server.conf | awk '{print $1}')
if /usr/lib/inithooks/bin/openvpn.py --profile=gateway \
        --key-email=admin@example.invalid \
        --public-address=$'localhost\npush "route 0.0.0.0 0.0.0.0"' \
        --virtual-subnet=10.231.0.0/24 >/dev/null 2>&1; then
    echo "newline-bearing public address was accepted" >&2
    exit 1
fi
test "$(sha256sum /etc/openvpn/server.conf | awk '{print $1}')" = \
    "$server_config_sha"
if /usr/lib/inithooks/bin/openvpn.py --profile=gateway \
        --key-email=admin@example.invalid --public-address=localhost \
        --virtual-subnet=10.231.0.1/24 >/dev/null 2>&1; then
    echo "host-address virtual subnet was accepted" >&2
    exit 1
fi
test "$(sha256sum /etc/openvpn/server.conf | awk '{print $1}')" = \
    "$server_config_sha"

default_interface=$(
    ip -4 route show default |
        awk '$1 == "default" {
            for (field = 1; field <= NF; field++) {
                if ($field == "dev" && field < NF) {
                    print $(field + 1); exit
                }
            }
        }'
)
test -n "$default_interface"
read -r recorded_interface recorded_source \
    </run/openvpn-masquerade.interface
read -r vpn_network vpn_netmask < <(
    awk '$1 == "server" && NF == 3 {print $2, $3; exit}' \
        /etc/openvpn/server.conf
)
test "$recorded_interface" = "$default_interface"
test "$recorded_source" = "$vpn_network/$vpn_netmask"
iptables -t nat -C POSTROUTING -s "$recorded_source" \
    -o "$default_interface" -m comment --comment turnkey-openvpn \
    -j MASQUERADE
test "$(count_nat_rules "$default_interface")" = 1

openvpn-addclient "$client_name" client@example.invalid "$private_subnet"
client_created=true
source_profile=/etc/openvpn/easy-rsa/keys/$client_name.ovpn
ccd_file=/etc/openvpn/server.ccd/$client_name
test "$(stat -c %a "$source_profile")" = 600
test "$(stat -c %a "/etc/openvpn/easy-rsa/keys/private/$client_name.key")" = 600
test "$(stat -c %a:%U:%G /etc/openvpn/easy-rsa/keys/crl.jail)" = \
    750:root:nogroup
test "$(stat -Lc %a:%U:%G /etc/openvpn/server.ccd)" = 750:root:nogroup
test "$(stat -c %a:%U:%G "$ccd_file")" = 640:root:nogroup
grep -Fxq 'iroute 198.51.100.0 255.255.255.0' "$ccd_file"
if find /etc/openvpn/easy-rsa/keys/private -type f -perm /077 -print -quit |
        grep -q .; then
    echo "private key material is group/world accessible" >&2
    exit 1
fi
if openvpn-addclient '../invalid' client@example.invalid >/dev/null 2>&1; then
    echo "path-bearing client name was accepted" >&2
    exit 1
fi
if /var/www/openvpn/bin/addprofile '../invalid' >/dev/null 2>&1; then
    echo "path-bearing published-profile name was accepted" >&2
    exit 1
fi
download_url=$(/var/www/openvpn/bin/addprofile "$client_name")
[[ $download_url =~ ^https://localhost/profiles/[a-f0-9]{48}/$ ]]
profile_path=${download_url#https://localhost}
published_profile=/var/www/openvpn/htdocs${profile_path%/}
profile_token=${profile_path%/}
profile_token=${profile_token##*/}
test "$(stat -c %a "$published_profile")" = 750
test "$(stat -c %a "$published_profile/$client_name.ovpn")" = 440
profile_diagnostics post-creation
systemctl restart openvpn@server.service
systemctl --quiet is-active openvpn@server.service
profile_diagnostics post-openvpn-restart

ip netns add "$namespace"
ip link add "$host_veth" type veth peer name "$client_veth"
ip address add 192.0.2.1/30 dev "$host_veth"
ip link set "$host_veth" up
ip link set "$client_veth" netns "$namespace"
ip netns exec "$namespace" ip link set lo up
ip netns exec "$namespace" ip address add 192.0.2.2/30 dev "$client_veth"
ip netns exec "$namespace" ip link set "$client_veth" up
ip netns exec "$namespace" ip route add default via 192.0.2.1

awk '
    $1 == "remote" { print "remote 192.0.2.1 1194"; next }
    { print }
' "$source_profile" >"$client_profile"
chmod 600 "$client_profile"
ip netns exec "$namespace" openvpn --config "$client_profile" \
    --daemon --writepid "$client_pid" --log "$client_log"
wait_for_client_tunnel

server_tunnel_ip=$(ip -4 -o address show dev tun0 |
    awk 'NR == 1 {sub(/\/.*/, "", $4); print $4}')
test -n "$server_tunnel_ip"
ip netns exec "$namespace" curl --insecure --fail --location --silent \
    --show-error --noproxy '*' --header 'Host: localhost' \
    --interface tun0 --max-time 20 \
    "https://$server_tunnel_ip/" >"$response"
test -s "$response"
if ip netns exec "$namespace" curl --insecure --fail --silent --show-error \
        --noproxy '*' --header 'Host: localhost' --interface tun0 --max-time 20 \
        "https://$server_tunnel_ip$profile_path" >"$response"; then
    profile_diagnostics post-profile-curl
else
    status=$?
    profile_diagnostics post-profile-curl-failure
    exit "$status"
fi
grep -Fq "$client_name.ovpn" "$response"
ip netns exec "$namespace" curl --insecure --fail --silent --show-error \
    --noproxy '*' --header 'Host: localhost' --interface tun0 --max-time 20 \
    "https://$server_tunnel_ip$profile_path$client_name.ovpn" >"$response"
cmp "$response" "$source_profile"
ip -4 route show exact "$private_subnet" | grep -Eq 'dev tun[0-9]+'
if journalctl -u openvpn@server.service -b --no-pager |
        grep -Fq "Could not access file '$ccd_file'"; then
    echo "OpenVPN could not read the client-config file" >&2
    exit 1
fi
for _attempt in {1..10}; do
    if grep -Fq "/profiles/$profile_token/$client_name.ovpn" \
            /var/www/openvpn/logs/access.log; then
        break
    fi
    sleep 1
done
grep -Fq "/profiles/$profile_token/$client_name.ovpn" \
    /var/www/openvpn/logs/access.log
su www-data -s /bin/bash -c /var/www/openvpn/bin/delexpired
test ! -e "$published_profile"
published_profile=

# The gateway profile must carry a real HTTPS request through the tunnel and
# the appliance's default-route masquerade rule, not merely create tun0.
debian_ip=$(getent ahostsv4 deb.debian.org |
    awk '$2 == "STREAM" {print $1; exit}')
test -n "$debian_ip"
ip netns exec "$namespace" ip -4 route get "$debian_ip" |
    grep -Eq 'dev tun[0-9]+'
ip netns exec "$namespace" curl --fail --silent --show-error \
    --noproxy '*' --interface tun0 --max-time 30 \
    --resolve "deb.debian.org:443:$debian_ip" \
    https://deb.debian.org/debian/README >"$response"
test -s "$response"

systemctl restart openvpn@server.service openvpn-masquerade.service
wait_for_client_tunnel
systemctl --quiet is-active openvpn@server.service \
    openvpn-masquerade.service
read -r recorded_interface recorded_source \
    </run/openvpn-masquerade.interface
test "$recorded_interface" = "$default_interface"
test "$recorded_source" = "$vpn_network/$vpn_netmask"
test "$(count_nat_rules "$default_interface")" = 1
ip netns exec "$namespace" curl --insecure --fail --location --silent \
    --show-error --noproxy '*' --header 'Host: localhost' \
    --interface tun0 --max-time 20 \
    "https://$server_tunnel_ip/" >"$response"
test -s "$response"

kill "$(cat "$client_pid")"
rm -f -- "$client_pid"
ip netns delete "$namespace"
openvpn-removeclient "$client_name" >/dev/null
client_created=false
test ! -e "$source_profile"
test ! -e "$ccd_file"
if grep -Fq "# subnet behind a client: $client_name" \
        /etc/openvpn/server.conf; then
    echo "revoked client route remained in the server configuration" >&2
    exit 1
fi
grep -Fq "$client_name" /etc/openvpn/easy-rsa/keys/index.txt
grep -Eq "^R.*CN=$client_name$" /etc/openvpn/easy-rsa/keys/index.txt
systemctl restart openvpn@server.service
systemctl --quiet is-active openvpn@server.service

openvpn_version=$(dpkg-query -W -f='${Version}' openvpn)
easy_rsa_version=$(dpkg-query -W -f='${Version}' easy-rsa)
iptables_version=$(dpkg-query -W -f='${Version}' iptables)
before="$openvpn_version|$easy_rsa_version|$iptables_version"
apt-get update >/dev/null
for package in openvpn easy-rsa iptables; do
    apt-cache policy "$package" >"$policy"
    candidate=$(awk '/Candidate:/ {print $2}' "$policy")
    test -n "$candidate"
    test "$candidate" != '(none)'
    grep -Eq 'deb\.debian\.org/debian.*trixie|security\.debian\.org/debian-security.*trixie-security' \
        "$policy"
done
after="$(dpkg-query -W -f='${Version}' openvpn)|$(dpkg-query -W -f='${Version}' easy-rsa)|$(dpkg-query -W -f='${Version}' iptables)"
test "$after" = "$before"
grep -Rqs '^Suites: trixie' /etc/apt/sources.list.d
if grep -Rqi bookworm /etc/apt/sources.list /etc/apt/sources.list.d \
        2>/dev/null; then
    echo "active Bookworm APT source found" >&2
    exit 1
fi

cat >"$result" <<EOF
package_source=Debian 13 Trixie APT repositories for OpenVPN, Easy-RSA and iptables; TurnKey APT for the inherited Core and Webmin components
installed_version=openvpn $openvpn_version; easy-rsa $easy_rsa_version; iptables $iptables_version
runtime_checks=normal init and firstboot; PKI and certificate-authenticated disposable client; real tun data transfer and gateway HTTPS egress; dynamic subnet-scoped default-interface NAT; least-privileged client key files; rejected config and path injection; random HTTPS profile publication and expiry; client revocation; OpenVPN and NAT restart persistence; Lighttpd landing page
updater_command=apt-get update; apt-cache policy openvpn easy-rsa iptables
updater_result=signed metadata refreshed; eligible candidates found; installed versions unchanged
updater_channel=Debian Trixie and TurnKey Trixie APT repositories
integrity_evidence=APT accepted signed repository metadata through configured Deb822 sources and keyrings; no Bookworm source remained
EOF
