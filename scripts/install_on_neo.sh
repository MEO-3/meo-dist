#!/usr/bin/env bash
# ==============================================================================
# MEO 3 gateway installer
# Installs the MEO 3 .deb (Java service + Rust BLE service + Node-RED) from this
# repo's GitHub Releases onto a NEO One / Nano Pi / Raspberry Pi.
#
# Usage:
#   Local:  bash scripts/install_on_neo.sh
#   Remote: curl -sSL https://raw.githubusercontent.com/MEO-3/meo-dist/main/scripts/install_on_neo.sh | bash
#
# Options:
#   --version=X.Y.Z   install a specific release (default: latest)
#   --uninstall       remove MEO 3, keep /var/lib/meo-3
#   --purge           remove MEO 3 and its data
# ==============================================================================
set -euo pipefail

REPO="MEO-3/meo-dist"
PKG="meo-3"
RAW_URL="https://raw.githubusercontent.com/${REPO}/main/scripts/install_on_neo.sh"

VERSION=""
ACTION="install"

for arg in "$@"; do
    case "$arg" in
        --version=*) VERSION="${arg#*=}"; VERSION="${VERSION#v}" ;;
        --uninstall) ACTION="remove" ;;
        --purge)     ACTION="purge" ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

info()  { echo -e "\033[1;32m[INFO]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# -E so a proxy env survives into apt and the NodeSource setup script.
SUDO="sudo -E"
if [ "$(id -u)" -eq 0 ]; then SUDO=""; fi

# -- uninstall ----------------------------------------------------------------
if [ "$ACTION" != "install" ]; then
    info "Removing $PKG ($ACTION)..."
    $SUDO apt-get "$ACTION" -y "$PKG"
    if [ "$ACTION" = "remove" ]; then
        info "Data kept in /var/lib/meo-3 (re-run with --purge to remove it)."
    fi
    exit 0
fi

# -- pre-flight ---------------------------------------------------------------
for c in curl apt-get; do
    command -v "$c" >/dev/null 2>&1 || { error "'$c' is required but not found."; exit 1; }
done

ARCH="$(dpkg --print-architecture)"      # arm64 on NEO One, amd64 on dev boxes
info "Detected architecture: $ARCH"

# The .deb hard-depends on nodejs (>= 22.9) and Armbian/Bookworm ship older, so
# apt would stop at unmet deps. Bootstrap only — the 22.0-22.8 gap is the .deb's
# to catch.
node_major="$(node -v 2>/dev/null | sed 's/v\([0-9]*\).*/\1/')"
if [ "${node_major:-0}" -lt 22 ]; then
    info "Installing Node.js 22 from NodeSource (found: ${node_major:-none})..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO bash -
    $SUDO apt-get install -y nodejs
fi

# -- resolve version ----------------------------------------------------------
if [ -z "$VERSION" ]; then
    info "Resolving latest release..."
    # One sed that reads to EOF: an early-exiting consumer (grep -m1, head -1)
    # gives curl EPIPE mid-body, and pipefail turns that into "curl: (23)".
    VERSION="$(curl -sSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p')" || true
    [ -n "$VERSION" ] || { error "Could not resolve the latest release; pin one with --version=X.Y.Z"; exit 1; }
fi

DEB="${PKG}_${VERSION}_${ARCH}.deb"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/${DEB}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

info "Downloading $DEB..."
curl -fSL --progress-bar -o "$TMP/$DEB" "$URL" \
    || { error "Download failed: $URL"; error "Check the release exists: https://github.com/${REPO}/releases"; exit 1; }

# -- install ------------------------------------------------------------------
# postinst resolves Node-RED's npm dependencies, so this step needs network.
info "Installing $PKG $VERSION (sudo required)..."
$SUDO apt-get update -qq || info "apt-get update reported errors; continuing."
$SUDO apt-get install -y --allow-downgrades "$TMP/$DEB"

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo ""
info "MEO 3 $VERSION installed."
echo "  Node-RED editor : http://${IP:-localhost}:1880"
echo "  service API     : http://localhost:7070"
echo "  status          : meo-3 status"
echo "  uninstall       : curl -sSL $RAW_URL | bash -s -- --uninstall"
