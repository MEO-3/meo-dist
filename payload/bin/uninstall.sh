#!/usr/bin/env bash
# Remove the MEO 3 gateway. Keeps /var/lib/meo-3 (flows and device database)
# unless --purge is given.
set -euo pipefail

PREFIX=/opt/meo-3
CONF=/etc/meo-3
DATA=/var/lib/meo-3
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

[ "$(id -u)" -eq 0 ] || { echo "uninstall.sh must run as root" >&2; exit 1; }

echo "==> stopping services"
systemctl disable --now meo-node-red.service meo-service.service meo-ble.service 2>/dev/null || true
rm -f /lib/systemd/system/meo-{ble,service,node-red}.service
systemctl daemon-reload

echo "==> removing $PREFIX"
rm -rf "$PREFIX"
rm -f /etc/mosquitto/conf.d/meo-3.conf
systemctl restart mosquitto 2>/dev/null || true

if [ "$PURGE" -eq 1 ]; then
    echo "==> purging config and data"
    rm -rf "$CONF" "$DATA"
    userdel meo 2>/dev/null || true
else
    echo "kept: $CONF and $DATA (re-run with --purge to remove)"
fi
