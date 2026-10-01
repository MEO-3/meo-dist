#!/usr/bin/env bash
# Assemble the release tree at $STAGE/meo-3 from the sibling repos' build output.
# Every lookup fails with the searched paths rather than producing a half tree.
set -euo pipefail

ARCH="${ARCH:?ARCH not set}"
VERSION="${VERSION:?VERSION not set}"
SERVICE_DIR="${SERVICE_DIR:?SERVICE_DIR not set}"
NODERED_DIR="${NODERED_DIR:?NODERED_DIR not set}"
STAGE="${STAGE:-build/stage}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$STAGE/meo-3"

case "$ARCH" in
    x86_64) BLE_CANDIDATES=("target/x86_64-unknown-linux-gnu/release" "target/release") ;;
    arm64)  BLE_CANDIDATES=("target/aarch64-unknown-linux-gnu/release") ;;
    *) echo "unsupported ARCH: $ARCH (expected x86_64 or arm64)" >&2; exit 1 ;;
esac

die() { echo "stage: $*" >&2; exit 1; }

rm -rf "$ROOT"
mkdir -p "$ROOT"/{bin,service,node-red/modules,ble,config,systemd,data}

# --- Java service (installDist output: bin/ launcher + lib/*.jar) -----------
JAVA_DIST="$SERVICE_DIR/build/install/meo-edge"
[ -d "$JAVA_DIST" ] || die "Java service not staged. Missing: $JAVA_DIST
Build it first: make -C $SERVICE_DIR build"
cp -a "$JAVA_DIST/." "$ROOT/service/"
rm -f "$ROOT"/service/bin/*.bat   # gateways are Linux-only

# --- Rust BLE binary, arch-matched -----------------------------------------
BLE_DIR="$SERVICE_DIR/rust/meo-helper"
BLE_BIN=""
for c in "${BLE_CANDIDATES[@]}"; do
    if [ -f "$BLE_DIR/$c/meo-helper" ]; then
        BLE_BIN="$BLE_DIR/$c/meo-helper"
        break
    fi
done
if [ -z "$BLE_BIN" ]; then
    searched=""
    for c in "${BLE_CANDIDATES[@]}"; do
        searched="$searched
  $BLE_DIR/$c/meo-helper"
    done
    die "BLE binary for $ARCH not found. Looked in:$searched
Build it first: make -C $SERVICE_DIR ble-$([ "$ARCH" = arm64 ] && echo arm || echo x86)"
fi
install -m 0755 "$BLE_BIN" "$ROOT/ble/meo-helper"

# Reject a host-built binary staged for the wrong architecture.
case "$ARCH" in
    x86_64) want="x86-64" ;;
    arm64)  want="aarch64" ;;
esac
if command -v file >/dev/null 2>&1; then
    file -b "$ROOT/ble/meo-helper" | grep -qi "$want" \
        || die "BLE binary is not $want: $(file -b "$ROOT/ble/meo-helper")"
fi

# A host cargo build on a modern distro requires a glibc newer than the target
# gateways have, and the binary then fails to start with a linker error. Catch
# that here rather than on a Raspberry Pi. GLIBC_FLOOR is Debian/Pi OS bookworm.
GLIBC_FLOOR="${GLIBC_FLOOR:-2.36}"
if command -v readelf >/dev/null 2>&1; then
    needed="$(readelf -V "$ROOT/ble/meo-helper" 2>/dev/null \
        | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -uV | tail -1)"
    if [ -n "$needed" ] \
       && [ "$(printf '%s\n%s\n' "$GLIBC_FLOOR" "$needed" | sort -V | tail -1)" != "$GLIBC_FLOOR" ]; then
        die "BLE binary requires glibc $needed but gateways have $GLIBC_FLOOR.
It was built against this host's glibc. Rebuild it with cross:
  make -C $SERVICE_DIR ble-$([ "$ARCH" = arm64 ] && echo arm || echo x86-dist)"
    fi
fi

# --- Node-RED: the packed module tarballs from `npm run release` ------------
NR_MODULES="$NODERED_DIR/.dist/modules"
[ -d "$NR_MODULES" ] || die "Node-RED release output missing: $NR_MODULES
Build it first: (cd $NODERED_DIR && npm run release)"
shopt -s nullglob
tgz=("$NR_MODULES"/*.tgz)
shopt -u nullglob
[ ${#tgz[@]} -gt 0 ] || die "no .tgz packages in $NR_MODULES"
cp -a "${tgz[@]}" "$ROOT/node-red/modules/"

# --- payload (scripts, config presets, units) ------------------------------
cp -a "$HERE/payload/bin/." "$ROOT/bin/"
cp -a "$HERE/payload/config/." "$ROOT/config/"
cp -a "$HERE/payload/systemd/." "$ROOT/systemd/"
chmod 0755 "$ROOT"/bin/*

# The JRE the service actually needs depends on which JDK built it, so read it
# out of the bytecode instead of assuming. Class major 65 = Java 21.
JAVA_REQ=""
main_jar="$(ls "$ROOT"/service/lib/meo-edge-*.jar 2>/dev/null | head -1 || true)"
if [ -n "$main_jar" ] && command -v unzip >/dev/null 2>&1; then
    cls="$(unzip -Z1 "$main_jar" | grep -m1 '\.class$' || true)"
    if [ -n "$cls" ]; then
        # Bytes 6-7 are the big-endian major version; combine them numerically so
        # a leading zero is not read as octal.
        major="$(unzip -p "$main_jar" "$cls" | od -An -tu1 -j6 -N2 | awk '{print $1*256 + $2}')"
        JAVA_REQ="$(( major - 44 ))"
        # Packages depend on a 21 JRE; anything newer would install but not run.
        [ "$JAVA_REQ" -le 21 ] || die "service needs Java $JAVA_REQ, packages only require 21.
Rebuild with JDK 21 or older: JAVA_HOME=/usr/lib/jvm/java-21-openjdk make build-service"
    fi
fi

echo "$VERSION" > "$ROOT/VERSION"
printf 'version=%s\narch=linux-%s\nbuilt=%s\njava_runtime=%s\n' \
    "$VERSION" "$ARCH" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${JAVA_REQ:-17}" > "$ROOT/BUILD_INFO"

echo "staged: $ROOT (version $VERSION, linux-$ARCH, ${#tgz[@]} node-red packages, needs java ${JAVA_REQ:-unknown})"
