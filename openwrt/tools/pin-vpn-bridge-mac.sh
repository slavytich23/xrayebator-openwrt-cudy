#!/bin/sh
set -eu

# Preserve this router's current gateway identity without a network reload.
[ "$(uci -q get network.br_vpn.name)" = br-vpn ]
[ -z "$(uci changes network)" ] || {
	echo 'PENDING_NETWORK_CHANGES=true' >&2
	exit 1
}
current=$(cat /sys/class/net/br-vpn/address)
printf '%s\n' "$current" | grep -Eq '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'
if [ "${APPLY_CHANGES:-0}" != 1 ]; then
	echo 'PREFLIGHT_OK=true'
	echo 'APPLY_REQUIRED=true'
	exit 0
fi
backup="/root/pre-vpn-mac-pin-$(date +%Y%m%d-%H%M%S)"
[ ! -e "$backup" ]
umask 077
cp /etc/config/network "$backup"
echo "NETWORK_BACKUP=$backup"
ip link set dev br-vpn address "$current"
uci set "network.br_vpn.macaddr=$current"
uci commit network
[ "$(cat /sys/class/net/br-vpn/address)" = "$current" ]
[ "$(uci get network.br_vpn.macaddr)" = "$current" ]
[ "$(cat /sys/class/net/br-vpn/addr_assign_type)" = 3 ]
echo 'BRIDGE_MAC_PINNED=true'
