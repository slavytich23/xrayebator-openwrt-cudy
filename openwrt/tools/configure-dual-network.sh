#!/bin/sh

set -eu

APPLY_CHANGES="${APPLY_CHANGES:-0}"
RELOAD_NETWORK="${RELOAD_NETWORK:-1}"
VPN_PORT="${VPN_PORT:-lan1}"
DIRECT_SSID="${DIRECT_SSID:-Direct}"
VPN_SSID="${VPN_SSID:-Xrayebator}"
DIRECT_WIFI_KEY_FILE="${DIRECT_WIFI_KEY_FILE:-}"
VPN_WIFI_KEY_FILE="${VPN_WIFI_KEY_FILE:-}"
STTY_STATE=''
KEY_RESULT=''
BACKUP_DIR=''
APPLY_STARTED=0
RELOAD_STARTED=0

restore_terminal() {
	if [ -n "$STTY_STATE" ]; then
		stty "$STTY_STATE" >/dev/null 2>&1 || true
		STTY_STATE=''
	fi
}

fail() {
	echo "$1" >&2
	exit "${2:-1}"
}

restore_backup() {
	rollback_ok=true
	for package in network wireless dhcp firewall xrayebator_safe; do
		uci -q revert "$package" >/dev/null 2>&1 || true
		if [ -s "$BACKUP_DIR/$package" ]; then
			cp "$BACKUP_DIR/$package" "/etc/config/$package" || rollback_ok=false
			chmod 600 "/etc/config/$package" || rollback_ok=false
		else
			rollback_ok=false
		fi
	done
	if [ "$RELOAD_STARTED" = 1 ]; then
		/etc/init.d/network reload >/dev/null 2>&1 || rollback_ok=false
		/etc/init.d/firewall restart >/dev/null 2>&1 || rollback_ok=false
		/etc/init.d/dnsmasq restart >/dev/null 2>&1 || rollback_ok=false
		wifi reload >/dev/null 2>&1 || rollback_ok=false
	fi
	if [ "$rollback_ok" = true ]; then
		echo 'AUTOMATIC_ROLLBACK_APPLIED=true' >&2
	else
		echo 'AUTOMATIC_ROLLBACK_APPLIED=false' >&2
	fi
}

on_exit() {
	rc=$?
	trap - EXIT INT TERM
	restore_terminal
	if [ "$rc" -ne 0 ] && [ "$APPLY_STARTED" = 1 ] && [ -d "$BACKUP_DIR" ]; then
		restore_backup
	fi
	exit "$rc"
}

trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

validate_token() {
	case "$1" in
		''|*[!a-zA-Z0-9_.:-]*) return 1 ;;
	esac
}

validate_ssid() {
	length="$(printf '%s' "$1" | wc -c)"
	[ "$length" -ge 1 ] && [ "$length" -le 32 ]
}

validate_key() {
	length="$(printf '%s' "$1" | wc -c)"
	[ "$length" -ge 8 ] && [ "$length" -le 63 ]
}

read_key() {
	label="$1"
	key_file="$2"
	KEY_RESULT=''
	if [ -n "$key_file" ]; then
		[ -r "$key_file" ] || fail "KEY_FILE_UNREADABLE=$label" 2
		KEY_RESULT="$(cat "$key_file")"
		return 0
	fi
	[ -t 0 ] || fail "KEY_FILE_REQUIRED_FOR_NONINTERACTIVE_RUN=$label" 2
	printf '%s: ' "$label Wi-Fi key" >&2
	STTY_STATE="$(stty -g)"
	stty -echo
	IFS= read -r KEY_RESULT
	restore_terminal
	printf '\n' >&2
}

find_device_section() {
	target_name="$1"
	for section in $(uci -q show network | sed -n "s/^\(network\.[^=]*\)=device$/\1/p"); do
		if [ "$(uci -q get "${section}.name" 2>/dev/null || true)" = "$target_name" ]; then
			printf '%s\n' "$section"
			return 0
		fi
	done
	return 1
}

validate_token "$VPN_PORT" || fail 'VPN_PORT_INVALID=true' 2
validate_ssid "$DIRECT_SSID" || fail 'DIRECT_SSID_INVALID=true' 2
validate_ssid "$VPN_SSID" || fail 'VPN_SSID_INVALID=true' 2
if [ -x /etc/init.d/xrayebator-safe ] && \
	/etc/init.d/xrayebator-safe running >/dev/null 2>&1; then
	fail 'XRAYEBATOR_SAFE_MUST_BE_STOPPED=true' 3
fi

BR_LAN_SECTION="$(find_device_section br-lan)" || fail 'BR_LAN_SECTION_NOT_FOUND=true' 3
case " $(uci -q get "${BR_LAN_SECTION}.ports") " in
	*" $VPN_PORT "*) ;;
	*) fail 'VPN_PORT_NOT_IN_BR_LAN=true' 3 ;;
esac

if [ "$APPLY_CHANGES" != 1 ]; then
	echo 'PREFLIGHT_OK=true'
	echo 'APPLY_REQUIRED=true'
	echo "VPN_PORT=$VPN_PORT"
	exit 0
fi

read_key DIRECT "$DIRECT_WIFI_KEY_FILE"
DIRECT_KEY="$KEY_RESULT"
read_key VPN "$VPN_WIFI_KEY_FILE"
VPN_KEY="$KEY_RESULT"
KEY_RESULT=''
validate_key "$DIRECT_KEY" || fail 'DIRECT_WIFI_KEY_INVALID=true' 2
validate_key "$VPN_KEY" || fail 'VPN_WIFI_KEY_INVALID=true' 2

BACKUP_DIR="/root/pre-dual-network-$(date +%Y%m%d-%H%M%S)"
[ ! -e "$BACKUP_DIR" ] || fail 'BACKUP_DIRECTORY_ALREADY_EXISTS=true' 4
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
for name in network wireless dhcp firewall xrayebator_safe; do
	[ -s "/etc/config/$name" ] || fail "CONFIG_MISSING=$name" 4
	cp "/etc/config/$name" "$BACKUP_DIR/$name"
	chmod 600 "$BACKUP_DIR/$name"
done
APPLY_STARTED=1

uci -q del_list "${BR_LAN_SECTION}.ports=$VPN_PORT"
uci -q set network.br_vpn='device'
uci -q set network.br_vpn.name='br-vpn'
uci -q set network.br_vpn.type='bridge'
uci -q set network.br_vpn.bridge_empty='1'
uci -q del_list "network.br_vpn.ports=$VPN_PORT" || true
uci -q add_list "network.br_vpn.ports=$VPN_PORT"

uci -q set network.vpn='interface'
uci -q set network.vpn.device='br-vpn'
uci -q set network.vpn.proto='static'
uci -q set network.vpn.ipaddr='192.168.20.1'
uci -q set network.vpn.netmask='255.255.255.0'
uci -q set network.xrayebator='interface'
uci -q set network.xrayebator.proto='none'
uci -q set network.xrayebator.device='xrayebator0'

uci -q set dhcp.vpn='dhcp'
uci -q set dhcp.vpn.interface='vpn'
uci -q set dhcp.vpn.start='100'
uci -q set dhcp.vpn.limit='150'
uci -q set dhcp.vpn.leasetime='12h'
uci -q set dhcp.vpn.dhcpv4='server'
uci -q set dhcp.vpn.dhcpv6='disabled'
uci -q set dhcp.vpn.ra='disabled'
uci -q delete dhcp.vpn.dhcp_option || true
uci -q add_list dhcp.vpn.dhcp_option='6,1.1.1.1,8.8.8.8'

uci -q set firewall.vpn='zone'
uci -q set firewall.vpn.name='vpn'
uci -q set firewall.vpn.network='vpn'
uci -q set firewall.vpn.input='ACCEPT'
uci -q set firewall.vpn.output='ACCEPT'
uci -q set firewall.vpn.forward='REJECT'
uci -q set firewall.xrayebator='zone'
uci -q set firewall.xrayebator.name='xrayebator'
uci -q set firewall.xrayebator.network='xrayebator'
uci -q set firewall.xrayebator.input='REJECT'
uci -q set firewall.xrayebator.output='ACCEPT'
uci -q set firewall.xrayebator.forward='REJECT'
uci -q set firewall.vpn_to_xrayebator='forwarding'
uci -q set firewall.vpn_to_xrayebator.src='vpn'
uci -q set firewall.vpn_to_xrayebator.dest='xrayebator'
uci -q set firewall.xrayebator_to_vpn='forwarding'
uci -q set firewall.xrayebator_to_vpn.src='xrayebator'
uci -q set firewall.xrayebator_to_vpn.dest='vpn'

for radio in radio0 radio1; do
	case "$radio" in
		radio0) direct_section=direct_radio0; vpn_section=vpn_radio0 ;;
		radio1) direct_section=direct_radio1; vpn_section=vpn_radio1 ;;
	esac
	uci -q set "wireless.$direct_section=wifi-iface"
	uci -q set "wireless.$direct_section.device=$radio"
	uci -q set "wireless.$direct_section.mode=ap"
	uci -q set "wireless.$direct_section.network=lan"
	uci -q set "wireless.$direct_section.ssid=$DIRECT_SSID"
	uci -q set "wireless.$direct_section.encryption=psk2"
	uci -q set "wireless.$direct_section.key=$DIRECT_KEY"
	uci -q set "wireless.$direct_section.disabled=0"
	uci -q set "wireless.$vpn_section=wifi-iface"
	uci -q set "wireless.$vpn_section.device=$radio"
	uci -q set "wireless.$vpn_section.mode=ap"
	uci -q set "wireless.$vpn_section.network=vpn"
	uci -q set "wireless.$vpn_section.ssid=$VPN_SSID"
	uci -q set "wireless.$vpn_section.encryption=psk2"
	uci -q set "wireless.$vpn_section.key=$VPN_KEY"
	uci -q set "wireless.$vpn_section.disabled=0"
done

uci -q set xrayebator_safe.main='service'
uci -q set xrayebator_safe.main.client_network='vpn'
uci -q set xrayebator_safe.main.client_device='br-vpn'
uci -q set xrayebator_safe.main.client_subnet='192.168.20.0/24'
uci -q set xrayebator_safe.main.health_bridge='br-vpn'
uci -q set xrayebator_safe.main.health_address='192.168.20.252/24'
uci -q set xrayebator_safe.main.health_gateway='192.168.20.1'
uci -q set xrayebator_safe.main.health_dns_server='1.1.1.1'

for package in network dhcp firewall wireless xrayebator_safe; do
	uci commit "$package"
done
DIRECT_KEY=''
VPN_KEY=''

if [ "$RELOAD_NETWORK" != 1 ]; then
	echo 'DUAL_NETWORK_CONFIG_WRITTEN=true'
	echo 'RUNTIME_RELOAD_REQUIRED=true'
	echo "BACKUP_DIR=$BACKUP_DIR"
	exit 0
fi

RELOAD_STARTED=1
/etc/init.d/network reload
/etc/init.d/firewall restart
/etc/init.d/dnsmasq restart
wifi reload
sleep 12

[ "$(basename "$(readlink "/sys/class/net/$VPN_PORT/master" 2>/dev/null || true)")" = br-vpn ]
[ "$(ubus call network.interface.vpn status | jsonfilter -e '@.up')" = true ]
[ "$(uci -q get wireless.direct_radio0.ssid)" = "$DIRECT_SSID" ]
[ "$(uci -q get wireless.direct_radio1.ssid)" = "$DIRECT_SSID" ]
[ "$(uci -q get wireless.vpn_radio0.ssid)" = "$VPN_SSID" ]
[ "$(uci -q get wireless.vpn_radio1.ssid)" = "$VPN_SSID" ]

echo 'DUAL_NETWORK_ACTIVE=true'
echo 'LEGACY_SSIDS_RETAINED=true'
echo "VPN_PORT=$VPN_PORT"
echo "BACKUP_DIR=$BACKUP_DIR"
