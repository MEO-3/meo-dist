#!/usr/bin/env bash
# Install the MEO 3 gateway bundle onto this machine.
#
#   /opt/meo-3       program files
#   /etc/meo-3       config (preserved across upgrades)
#   /var/lib/meo-3   runtime data: meo.db, Node-RED userDir
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX=/opt/meo-3
CONF=/etc/meo-3
DATA=/var/lib/meo-3
SVC_USER=meo

[ "$(id -u)" -eq 0 ] || { echo "install.sh must run as root (try: sudo $0)" >&2; exit 1; }

info() { echo "==> $*"; }
die()  { echo "error: $*" >&2; exit 1; }

# --- dependency checks ------------------------------------------------------
# Fail with the exact command to run rather than installing things behind the
# user's back.
missing=()

# Set at build time from the service's bytecode version (see scripts/stage.sh).
JAVA_REQ="$(sed -n 's/^java_runtime=//p' "$SRC/BUILD_INFO" 2>/dev/null)"
JAVA_REQ="${JAVA_REQ:-21}"

java_ok=0
if command -v java >/dev/null 2>&1; then
    # "openjdk version "21.0.2"" / ""17.0.1"" -> major
    jv="$(java -version 2>&1 | head -1 | sed -n 's/.*version "\([0-9]*\).*/\1/p')"
    [ -n "$jv" ] && [ "$jv" -ge "$JAVA_REQ" ] && java_ok=1
    [ "$java_ok" -eq 1 ] || echo "   java $jv found, this build needs $JAVA_REQ or newer"
fi
[ "$java_ok" -eq 1 ] || missing+=("openjdk-${JAVA_REQ}-jre-headless")

node_ok=0
if command -v node >/dev/null 2>&1; then
    nv="$(node -v | sed 's/^v//')"
    nmaj="${nv%%.*}"; nrest="${nv#*.}"; nmin="${nrest%%.*}"
    if [ "$nmaj" -gt 22 ] || { [ "$nmaj" -eq 22 ] && [ "$nmin" -ge 9 ]; }; then
        node_ok=1
    else
        echo "   node $nv found, Node-RED needs >= 22.9"
    fi
fi
if [ "$node_ok" -eq 0 ]; then
    cat >&2 <<'EOF'
   Node.js >= 22.9 is required and Raspberry Pi OS Bookworm ships an older one.
   Install it with:
     curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
     sudo apt install -y nodejs
EOF
    missing+=("nodejs (>= 22.9, see above)")
fi

command -v mosquitto >/dev/null 2>&1 || missing+=("mosquitto")
command -v npm >/dev/null 2>&1 || missing+=("npm")

if [ ${#missing[@]} -gt 0 ]; then
    echo "" >&2
    echo "Missing dependencies: ${missing[*]}" >&2
    echo "Install them, then re-run this script." >&2
    exit 1
fi

# --- service user & directories --------------------------------------------
if ! id -u "$SVC_USER" >/dev/null 2>&1; then
    info "creating system user $SVC_USER"
    useradd --system --home-dir "$DATA" --shell /usr/sbin/nologin "$SVC_USER"
fi

info "installing to $PREFIX"
mkdir -p "$PREFIX" "$CONF" "$DATA/node-red"
rm -rf "$PREFIX"/{service,ble,bin,systemd}
cp -a "$SRC"/{service,ble,bin,systemd} "$PREFIX/"
cp -a "$SRC"/VERSION "$SRC"/BUILD_INFO "$PREFIX/" 2>/dev/null || true
mkdir -p "$PREFIX/node-red"
cp -a "$SRC/node-red/modules" "$PREFIX/node-red/"

# Config is never overwritten once installed — the gateway owns it.
for f in meo.env settings.js mosquitto-meo.conf; do
    if [ -e "$CONF/$f" ]; then
        info "keeping existing $CONF/$f (new version at $CONF/$f.dist)"
        cp -a "$SRC/config/$f" "$CONF/$f.dist"
    else
        cp -a "$SRC/config/$f" "$CONF/$f"
    fi
done
[ -e "$DATA/node-red/flows.json" ] || cp -a "$SRC/config/flows.json" "$DATA/node-red/flows.json"

# Branding is program data, not user config — always refreshed. settings.js
# points at this path.
rm -rf "$CONF/branding"
cp -a "$SRC/config/branding" "$CONF/branding"

# --- Node-RED runtime -------------------------------------------------------
# All seven packed packages are installed in one npm call so the @node-red/*
# tarballs satisfy node-red's own exact-version deps instead of the registry.
info "installing Node-RED (this pulls dependencies from npm, needs network)"
( cd "$PREFIX/node-red" \
  && printf '{\n  "name": "meo-3-node-red",\n  "private": true\n}\n' > package.json \
  && npm install --omit=dev --no-audit --no-fund ./modules/*.tgz )

chown -R "$SVC_USER":"$SVC_USER" "$DATA"

# --- broker -----------------------------------------------------------------
if [ -d /etc/mosquitto/conf.d ]; then
    info "installing mosquitto config"
    cp -a "$CONF/mosquitto-meo.conf" /etc/mosquitto/conf.d/meo-3.conf
    # Never swallow this: without the broker nothing MEO does works.
    systemctl restart mosquitto \
        || echo "warning: mosquitto failed to start — the gateway has no MQTT broker. Run: systemctl status mosquitto" >&2
else
    echo "warning: /etc/mosquitto/conf.d not found — configure the broker manually" >&2
fi

# --- systemd ----------------------------------------------------------------
info "installing systemd units"
cp -a "$PREFIX"/systemd/*.service /lib/systemd/system/
systemctl daemon-reload
systemctl enable --now meo-ble.service meo-service.service meo-node-red.service

echo ""
info "MEO 3 $(cat "$PREFIX/VERSION" 2>/dev/null || echo '') installed"
echo "    Node-RED editor : http://$(hostname -I 2>/dev/null | awk '{print $1}'):1880"
echo "    service API     : http://localhost:7070"
echo "    status          : $PREFIX/bin/meo-3 status"
