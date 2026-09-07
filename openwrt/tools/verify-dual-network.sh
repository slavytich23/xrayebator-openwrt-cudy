#!/bin/sh

set -eu

HEALTH_NAMESPACE="${XRAYEBATOR_HEALTH_NAMESPACE:-xrayhealth}"
DIRECT_SOURCE="${DIRECT_SOURCE:-$(uci -q get network.lan.ipaddr | cut -d/ -f1)}"
HTTPS_URL="${HTTPS_URL:-https://www.cloudflare.com/cdn-cgi/trace}"
EGRESS_URL="${EGRESS_URL:-https://api.ipify.org}"

command -v curl >/dev/null 2>&1
ip netns list | grep -q "^$HEALTH_NAMESPACE[[:space:]]"
[ -n "$DIRECT_SOURCE" ]

vpn_http="$(ip netns exec "$HEALTH_NAMESPACE" curl -L -sS -o /dev/null \
	-w '%{exitcode}|%{http_code}' --connect-timeout 8 --max-time 20 \
	"$HTTPS_URL" 2>/dev/null || true)"
direct_http="$(curl --interface "$DIRECT_SOURCE" -L -sS -o /dev/null \
	-w '%{exitcode}|%{http_code}' --connect-timeout 8 --max-time 20 \
	"$HTTPS_URL" 2>/dev/null || true)"
vpn_egress="$(ip netns exec "$HEALTH_NAMESPACE" curl -sS \
	--connect-timeout 8 --max-time 20 "$EGRESS_URL" 2>/dev/null || true)"
direct_egress="$(curl --interface "$DIRECT_SOURCE" -sS \
	--connect-timeout 8 --max-time 20 "$EGRESS_URL" 2>/dev/null || true)"

printf 'VPN_HTTP=%s\n' "$vpn_http"
printf 'DIRECT_HTTP=%s\n' "$direct_http"
[ -n "$vpn_egress" ] && [ -n "$direct_egress" ] && \
	echo 'EGRESS_VALUES_PRESENT=true' || echo 'EGRESS_VALUES_PRESENT=false'
[ -n "$vpn_egress" ] && [ -n "$direct_egress" ] && [ "$vpn_egress" != "$direct_egress" ] && \
	echo 'VPN_AND_DIRECT_EGRESS_DIFFER=true' || {
	echo 'VPN_AND_DIRECT_EGRESS_DIFFER=false'
	exit 1
}
