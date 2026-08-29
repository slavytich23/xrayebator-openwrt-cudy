#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
GUARD="$ROOT/openwrt/files/usr/libexec/xrayebator-safe/route-guard"
suffix="$$"
ns="xrg-$suffix"
host_if="xrh$suffix"
state_file="/run/xrg-$suffix.env"

cleanup() {
	set +e
	ip netns exec "$ns" env \
		XRAYEBATOR_LAN_DEVICE=lan0 \
		XRAYEBATOR_WAN_DEVICE=wan0 \
		XRAYEBATOR_LAN_SUBNET=192.168.250.0/24 \
		XRAYEBATOR_STATE_FILE="$state_file" \
		"$GUARD" cleanup >/dev/null 2>&1
	ip netns del "$ns" >/dev/null 2>&1
	ip link del "$host_if" >/dev/null 2>&1
}
trap cleanup EXIT INT TERM

ip netns add "$ns"
ip link add "$host_if" type veth peer name wan0 netns "$ns"
ip link set "$host_if" up
ip netns exec "$ns" ip link set lo up
ip netns exec "$ns" ip link set wan0 up
ip netns exec "$ns" ip link add lan0 type dummy
ip netns exec "$ns" ip link set lan0 up
ip netns exec "$ns" ip addr add 192.168.250.1/24 dev lan0
ip netns exec "$ns" ip link add xrayebator0 type dummy
ip netns exec "$ns" ip link set xrayebator0 up

ip netns exec "$ns" env \
	XRAYEBATOR_LAN_DEVICE=lan0 \
	XRAYEBATOR_WAN_DEVICE=wan0 \
	XRAYEBATOR_LAN_SUBNET=192.168.250.0/24 \
	XRAYEBATOR_STATE_FILE="$state_file" \
	"$GUARD" setup

status="$(ip netns exec "$ns" "$GUARD" status 2>&1)"
grep -q '^POLICY_INSTALLED=true$' <<<"$status"
grep -q '^TUN_ROUTE_ACTIVE=true$' <<<"$status"
ip netns exec "$ns" ip -4 rule show | grep -F 'from 192.168.250.0/24 iif lan0 lookup 5852'
ip netns exec "$ns" ip -4 route get 192.168.250.2 from 192.168.250.1 | grep -q 'dev lan0'
ip netns exec "$ns" nft list table inet xrayebator_safe | grep -q 'dnat ip to 1.1.1.1'

ip netns exec "$ns" ip link del xrayebator0
ip netns exec "$ns" ip -4 route show table 5852 | grep -q '^prohibit default'

ip netns exec "$ns" env \
	XRAYEBATOR_LAN_DEVICE=lan0 \
	XRAYEBATOR_WAN_DEVICE=wan0 \
	XRAYEBATOR_LAN_SUBNET=192.168.250.0/24 \
	XRAYEBATOR_STATE_FILE="$state_file" \
	"$GUARD" cleanup

if ip netns exec "$ns" ip -4 rule show | grep -q 'lookup 5852'; then
	echo 'POLICY_CLEANUP=false'
	exit 1
fi
if ip netns exec "$ns" nft list table inet xrayebator_safe >/dev/null 2>&1; then
	echo 'NFT_CLEANUP=false'
	exit 1
fi

echo 'ROUTE_GUARD_SETUP=true'
echo 'ROUTE_GUARD_FAIL_CLOSED=true'
echo 'ROUTE_GUARD_CLEANUP=true'
