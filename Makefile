WEBMIN_FW_TCP_INCOMING = 22 80 443 12321
WEBMIN_FW_UDP_INCOMING = 1194

COMMON_OVERLAYS = tkl-webcp timezone
COMMON_CONF = tkl-webcp

include $(FAB_PATH)/common/mk/turnkey/lighttpd.mk
include $(FAB_PATH)/common/mk/turnkey.mk
