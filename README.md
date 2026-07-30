# meo-3-dist

Release packaging for the MEO 3 gateway. This repo holds **no product source** — it
builds the sibling repos, stages their artifacts into one tree, and packages it.

Expected workspace layout:

```
meo-3/
├── meo-3-dist/          <- this repo
├── meo-3-open-service/  Java service + Rust BLE service
└── node-red-meo/        the MEO fork of Node-RED
```

## Build

```bash
make dist            # host arch
make dist-x86_64
make dist-arm64      # needs `cross` for the BLE binary
```

Build host needs **JDK 17–21** (the service's Gradle build fails on 22+, checked by
`make build-service`), **Node.js >= 22.9** + npm, and for `dist-arm64` the `cross`
crate plus a working Docker/Podman.

Output: `build/dist/meo-3-<version>-linux-<arch>.tar.gz`, which extracts to `meo-3/`:

```
meo-3/
├── bin/          meo-3 (start|stop|restart|status|logs), install.sh, uninstall.sh
├── service/      Java service: bin/ launcher + lib/*.jar
├── node-red/     modules/*.tgz  (node_modules/ appears at install time)
├── ble/          meo-3-neo-ble-service (arch-matched)
├── config/       meo.env, settings.js, flows.json, mosquitto-meo.conf, branding/
├── systemd/      meo-ble, meo-service, meo-node-red
└── data/         runtime home (meo.db, Node-RED userDir)
```

`make stage` builds the same tree without tarring, at `build/stage/meo-3`.

## Install on a gateway

```bash
tar -xzf meo-3-<version>-linux-arm64.tar.gz
sudo meo-3/bin/install.sh
```

Installs to `/opt/meo-3`, config to `/etc/meo-3` (never overwritten on upgrade — a
new version lands as `*.dist`), data to `/var/lib/meo-3`, and enables the three
systemd units. `sudo meo-3/bin/uninstall.sh [--purge]` reverses it.

Without root or systemd the tree also runs in place: `meo-3/bin/meo-3 start` spawns
the three processes and logs to `meo-3/run/`.

## Debian package

```bash
make deb            # host arch, from the staged tree
make deb-arm64
```

Output: `build/dist/meo-3_<version>_<amd64|arm64>.deb`. `dpkg-deb` is not on
non-Debian build hosts, so `scripts/deb.sh` runs it inside `debian:bookworm-slim`
via podman/docker automatically.

Install layout: `/opt/meo-3` (program files), `/etc/meo-3` (conffiles — dpkg
preserves your edits on upgrade), `/usr/share/meo-3` (branding + the flows
template), `/lib/systemd/system`, `/var/lib/meo-3` (data), `/usr/bin/meo-3`.
`postinst` creates the `meo` user, resolves Node-RED's deps, and enables the units;
`apt purge` removes everything including the generated `node_modules`.

```bash
sudo apt install ./meo-3_3.0.0_arm64.deb
```

**The JRE dependency is derived, not hardcoded.** `stage.sh` reads the service's
bytecode version and records it in `BUILD_INFO`; `deb.sh` turns that into
`Depends: openjdk-<n>-jre-headless`. Build with JDK 21 and the package requires
openjdk-21 — which **Debian 12 / Raspberry Pi OS Bookworm does not ship at all,
not even in backports** (17 is the newest there). For those gateways either build
the service with JDK 17, or use Debian 13 / a third-party JDK. Nothing needs
editing here: rebuild and the dependency follows.

The arm64 package is built and checked statically (correct `Architecture`, aarch64
ELF with a GLIBC_2.18 floor, byte-identical file layout to amd64, same lintian
result), but it has **not been run**: that needs a real gateway, or
`qemu-user-static` binfmt registered on the build host.

Verified against a real `apt install` in `debian:trixie-slim` — deps resolve, the
Node-RED install runs, units are enabled, the Java service binds `:7070`, and
`apt purge` leaves nothing behind. `lintian` is clean apart from
`dir-or-file-in-opt` / `jar-not-in-usr-share` (both inherent to shipping a bundled
app in `/opt`, which is correct for a package outside the Debian archive) and
`no-manual-page`.

## Host dependencies

Not bundled — `install.sh` verifies them and prints the install command:

| dependency | why |
| --- | --- |
| JRE matching the build JDK | the Java gateway service; `BUILD_INFO` records the version |
| Node.js >= 22.9 | Node-RED's `engines` floor; Pi OS Bookworm ships older, needs NodeSource |
| mosquitto | MQTT broker, a system dependency by design |
| npm | resolves Node-RED's dependencies at install time |

## Known constraints

- **Install needs network.** The bundle ships Node-RED as seven packed tarballs and
  `install.sh` runs `npm install --omit=dev` to resolve their dependencies. For
  offline gateways, bake a production `node_modules` into the package instead.
- **Broker must be on the gateway.** The Rust BLE service hardcodes
  `localhost:1883` and `meo-gateway` derives `mqtt://<host>:1883`; neither is
  configurable.
- **Firmware is not packaged.** `meo-3-arduino` ships to devices via PlatformIO.
- **Bookworm gateways need a Java decision.** See the Debian package section: a
  JDK-21 build cannot be installed on stock Raspberry Pi OS Bookworm.
- **BLE binaries must be cross-built.** A host `cargo build` on a modern distro
  links a glibc newer than the gateways have, and the binary then refuses to
  start. `make dist` uses `cross` for both arches and `stage.sh` fails the build
  if a binary's glibc floor exceeds `GLIBC_FLOOR` (2.36, Bookworm).
