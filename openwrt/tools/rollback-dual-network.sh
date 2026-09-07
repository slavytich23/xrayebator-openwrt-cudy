#!/bin/sh

set -eu

APPLY_CHANGES="${APPLY_CHANGES:-0}"
BACKUP_DIR="${1:-}"

case "$BACKUP_DIR" in
	/root/pre-dual-network-*|/root/pre-dual-finalize-*) ;;
	*) echo 'BACKUP_DIR_INVALID=true' >&2; exit 2 ;;
esac
case "${BACKUP_DIR#/root/}" in
	*/*) echo 'BACKUP_DIR_INVALID=true' >&2; exit 2 ;;
esac

[ -d "$BACKUP_DIR" ] || {
	echo 'BACKUP_DIR_MISSING=true' >&2
	exit 2
}
RESOLVED_BACKUP_DIR="$(readlink -f "$BACKUP_DIR" 2>/dev/null || true)"
[ "$RESOLVED_BACKUP_DIR" = "$BACKUP_DIR" ] || {
	echo 'BACKUP_DIR_REDIRECTED=true' >&2
	exit 2
}

if [ "$APPLY_CHANGES" != 1 ]; then
	echo 'PREFLIGHT_OK=true'
	echo 'APPLY_REQUIRED=true'
	exit 0
fi

restored=0
for name in network wireless dhcp firewall xrayebator_safe; do
	if [ -s "$BACKUP_DIR/$name" ]; then
		cp "$BACKUP_DIR/$name" "/etc/config/$name"
		chmod 600 "/etc/config/$name"
		restored=$((restored + 1))
	fi
done
[ "$restored" -gt 0 ]

/etc/init.d/network reload
/etc/init.d/firewall restart
/etc/init.d/dnsmasq restart
wifi reload

echo 'DUAL_NETWORK_ROLLBACK_APPLIED=true'
echo "RESTORED_FILES=$restored"
