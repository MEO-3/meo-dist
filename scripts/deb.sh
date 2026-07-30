#!/usr/bin/env bash
# Turn the staged tree ($STAGE/meo-3) into a .deb.
#
# Rearranges the same staging tree the tarball uses into FHS locations, then
# calls dpkg-deb. dpkg-deb is not available on non-Debian build hosts, so we
# fall back to running it inside a Debian container (podman or docker).
set -euo pipefail

ARCH="${ARCH:?ARCH not set}"
VERSION="${VERSION:?VERSION not set}"
STAGE="${STAGE:-build/stage}"
DIST="${DIST:-build/dist}"
DEB_BUILD="${DEB_BUILD:-build/deb}"
MAINTAINER="${DEB_MAINTAINER:-MEO 3 Project <maintainer@meo-3.invalid>}"
CONTAINER_IMAGE="${DEB_CONTAINER_IMAGE:-docker.io/library/debian:bookworm-slim}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$STAGE/meo-3"

case "$ARCH" in
    x86_64) DEB_ARCH=amd64 ;;
    arm64)  DEB_ARCH=arm64 ;;
    *) echo "unsupported ARCH: $ARCH" >&2; exit 1 ;;
esac

die() { echo "deb: $*" >&2; exit 1; }

[ -d "$SRC" ] || die "staged tree missing: $SRC
Run 'make stage' first."

PKGROOT="$DEB_BUILD/meo-3_${VERSION}_${DEB_ARCH}"
rm -rf "$PKGROOT"
mkdir -p "$PKGROOT"/{DEBIAN,opt/meo-3/bin,opt/meo-3/node-red,etc/meo-3,etc/mosquitto/conf.d,lib/systemd/system,usr/bin,usr/share/meo-3,usr/share/doc/meo-3,var/lib/meo-3}

# --- program files ----------------------------------------------------------
cp -a "$SRC/service" "$SRC/ble" "$PKGROOT/opt/meo-3/"
cp -a "$SRC/node-red/modules" "$PKGROOT/opt/meo-3/node-red/"
cp -a "$SRC/VERSION" "$SRC/BUILD_INFO" "$PKGROOT/opt/meo-3/"
# install.sh/uninstall.sh are the tarball's job; dpkg does it here.
install -m 0755 "$SRC/bin/meo-3" "$PKGROOT/opt/meo-3/bin/meo-3"
ln -sf /opt/meo-3/bin/meo-3 "$PKGROOT/usr/bin/meo-3"

# --- config -----------------------------------------------------------------
install -m 0644 "$SRC/config/meo.env" "$PKGROOT/etc/meo-3/meo.env"
install -m 0644 "$SRC/config/settings.js" "$PKGROOT/etc/meo-3/settings.js"
install -m 0644 "$SRC/config/mosquitto-meo.conf" "$PKGROOT/etc/mosquitto/conf.d/meo-3.conf"
# Branding is program data, not config; settings.js finds it here.
cp -a "$SRC/config/branding" "$PKGROOT/usr/share/meo-3/branding"
# Template only — postinst seeds it into the Node-RED userDir if absent.
install -m 0644 "$SRC/config/flows.json" "$PKGROOT/usr/share/meo-3/flows.json"

install -m 0644 "$SRC"/systemd/*.service "$PKGROOT/lib/systemd/system/"

cat > "$PKGROOT/usr/share/doc/meo-3/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: MEO 3
Source: https://github.com/thingai/meo-3

Files: *
Copyright: $(date +%Y) The MEO 3 Project
License: AGPL-3.0-or-later
 This program is free software: you can redistribute it and/or modify it under
 the terms of the GNU Affero General Public License as published by the Free
 Software Foundation, either version 3 of the License, or (at your option) any
 later version. On Debian systems the full text is at
 /usr/share/common-licenses/AGPL-3.

Files: opt/meo-3/node-red/*
Copyright: OpenJS Foundation and other contributors, https://openjsf.org/
License: Apache-2.0
 On Debian systems the full text is at /usr/share/common-licenses/Apache-2.0.
EOF

# Native package: dpkg wants a changelog, and gateways benefit from knowing
# which build they are on.
cat > "$DEB_BUILD/changelog" <<EOF
meo-3 ($VERSION) stable; urgency=medium

  * MEO 3 gateway bundle $VERSION (linux-$ARCH).
    See the VERSION and BUILD_INFO files in /opt/meo-3.

 -- ${MAINTAINER}  $(date -R)
EOF
gzip -9nc "$DEB_BUILD/changelog" > "$PKGROOT/usr/share/doc/meo-3/changelog.gz"
chmod 0644 "$PKGROOT/usr/share/doc/meo-3/changelog.gz"

# --- control ----------------------------------------------------------------
# The JRE dependency follows the bytecode the service was actually built with,
# recorded by scripts/stage.sh. Hardcoding it here would let a JDK-21 build ship
# a package that installs against a JRE too old to run it.
JAVA_REQ="$(sed -n 's/^java_runtime=//p' "$SRC/BUILD_INFO" 2>/dev/null)"
[ -n "$JAVA_REQ" ] || die "java_runtime missing from $SRC/BUILD_INFO; re-run 'make stage'."

sed -e "s|@VERSION@|$VERSION|" \
    -e "s|@DEB_ARCH@|$DEB_ARCH|" \
    -e "s|@MAINTAINER@|$MAINTAINER|" \
    -e "s|@JAVA_REQ@|$JAVA_REQ|g" \
    "$HERE/payload/debian/control.in" > "$PKGROOT/DEBIAN/control"

install -m 0644 "$HERE/payload/debian/conffiles" "$PKGROOT/DEBIAN/conffiles"
for s in postinst prerm postrm; do
    install -m 0755 "$HERE/payload/debian/$s" "$PKGROOT/DEBIAN/$s"
done

# --- build ------------------------------------------------------------------
mkdir -p "$DIST"
OUT="$DIST/meo-3_${VERSION}_${DEB_ARCH}.deb"
BUILD_CMD="dpkg-deb --root-owner-group --build \"$PKGROOT\" \"$OUT\""

if command -v dpkg-deb >/dev/null 2>&1; then
    eval "$BUILD_CMD"
else
    runtime=""
    for r in podman docker; do
        command -v "$r" >/dev/null 2>&1 && { runtime="$r"; break; }
    done
    [ -n "$runtime" ] || die "dpkg-deb not found and no podman/docker to run it in.
Build on a Debian host, or install podman."
    echo "deb: dpkg-deb not on this host, building in $CONTAINER_IMAGE via $runtime"
    "$runtime" run --rm -v "$HERE:/w:Z" -w /w "$CONTAINER_IMAGE" \
        sh -c "$BUILD_CMD"
fi

echo "packaged: $OUT"
