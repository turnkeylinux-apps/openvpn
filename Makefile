WEBMIN_FW_TCP_INCOMING = 22 80 443 12320 12321
WEBMIN_FW_UDP_INCOMING = 1194
WEBMIN_FW_NAT_EXTRA = -A POSTROUTING -o eth0 -j MASQUERADE

COMMON_OVERLAYS = tkl-webcp timezone
COMMON_CONF = tkl-webcp

include $(FAB_PATH)/common/mk/turnkey/lighttpd.mk
include $(FAB_PATH)/common/mk/turnkey.mk
