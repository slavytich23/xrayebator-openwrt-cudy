#!/bin/sh

set -eu

APPLY_CHANGES="${APPLY_CHANGES:-0}"
LEGACY_SECTIONS="${LEGACY_SECTIONS:-default_radio0 default_radio1}"
BACKUP_DIR=''
APPLY_STARTED=0
RELOAD_STARTED=0

restore_wireless() {
	rollback_ok=true
	uci -q revert wireless >/dev/null 2>&1 || true
	cp "$BACKUP_DIR/wireless" /etc/config/wireless || rollback_ok=false
	chmod 600 /etc/config/wireless || rollback_ok=false
	if [ "$RELOAD_STARTED" = 1 ]; then
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
	if [ "$rc" -ne 0 ] && [ "$APPLY_STARTED" = 1 ] && [ -s "$BACKUP_DIR/wireless" ]; then
		restore_wireless
	fi
	exit "$rc"
}

trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for section in direct_radio0 direct_radio1 vpn_radio0 vpn_radio1; do
	[ "$(uci -q get "wireless.$section.disabled")" = 0 ] || {
		echo "CUSTOM_WIFI_NOT_READY=$section" >&2
		exit 2
	}
done

for section in $LEGACY_SECTIONS; do
	case "$section" in
		''|*[!a-zA-Z0-9_]* ) echo 'LEGACY_SECTION_INVALID=true' >&2; exit 2 ;;
	esac
	uci -q get "wireless.$section" >/dev/null || {
		echo "LEGACY_SECTION_MISSING=$section" >&2
		exit 2
	}
done

if [ "$APPLY_CHANGES" != 1 ]; then
	echo 'PREFLIGHT_OK=true'
	echo 'APPLY_REQUIRED=true'
	exit 0
fi

BACKUP_DIR="/root/pre-dual-finalize-$(date +%Y%m%d-%H%M%S)"
[ ! -e "$BACKUP_DIR" ] || {
	echo 'BACKUP_DIRECTORY_ALREADY_EXISTS=true' >&2
	exit 4
}
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
cp /etc/config/wireless "$BACKUP_DIR/wireless"
chmod 600 "$BACKUP_DIR/wireless"
APPLY_STARTED=1

for section in $LEGACY_SECTIONS; do
	uci -q set "wireless.$section.disabled=1"
done
uci commit wireless
RELOAD_STARTED=1
wifi reload
sleep 12

for section in $LEGACY_SECTIONS; do
	[ "$(uci -q get "wireless.$section.disabled")" = 1 ]
done
[ "$(iw dev 2>/dev/null | grep -c '^[[:space:]]*Interface ')" -ge 4 ]

echo 'LEGACY_SSIDS_DISABLED=true'
echo 'UNIFIED_SSIDS_ACTIVE=true'
echo "BACKUP_DIR=$BACKUP_DIR"
