# meo-dist

Release packaging for the MEO 3 gateway. This repo holds **no product source** — it builds the sibling repos, stages their artifacts into one tree, and packages it.

Expected workspace layout:

```
meo-3/
├── meo-dist/          <- this repo
├── meo-edge/  Java service + Rust BLE service
└── node-red-meo/        the MEO fork of Node-RED
```

## Build

```bash
make dist            # host arch: tarball
make dist-arm64      # needs `cross` for the BLE binary
make deb             # .deb for the host arch, from the staged tree
make deb-arm64
make stage           # the tree alone, at build/stage/meo-3, no tarring
```

Build host needs **JDK 17–21** (the service's Gradle build fails on 22+, checked by `make build-service`), **Node.js >= 22.9** + npm, and podman/docker — `dpkg-deb` is absent on non-Debian hosts, so `scripts/deb.sh` runs it in `debian:bookworm-slim`.

Output lands in `build/dist/`. The tarball extracts to `meo-3/`:

```
meo-3/
├── bin/          meo-3 (start|stop|restart|status|logs), install.sh, uninstall.sh
├── service/      Java service: bin/ launcher + lib/*.jar
├── node-red/     modules/*.tgz  (node_modules/ appears at install time)
├── ble/          meo-helper (arch-matched)
├── config/       meo.env, settings.js, flows.json, mosquitto-meo.conf, branding/
├── systemd/      meo-ble, meo-service, meo-node-red
└── data/         runtime home (meo.db, Node-RED userDir)
```

## Install on a gateway

```bash
curl -sSL https://raw.githubusercontent.com/MEO-3/meo-dist/main/scripts/install_on_neo.sh | bash
```

`scripts/install_on_neo.sh` resolves the latest release and installs the .deb for the host architecture. It adds the NodeSource repository when the host's Node.js is older than 22, without which the `nodejs (>= 22.9)` dependency is unsatisfiable on stock Armbian and Raspberry Pi OS. `--version=X.Y.Z` pins a release; `--uninstall` (or `--purge`) reverses it.

By hand, from a downloaded artifact:

```bash
sudo apt install ./meo-3_<version>_arm64.deb
# or, anywhere / without root:
tar -xzf meo-3-<version>-linux-arm64.tar.gz && sudo meo-3/bin/install.sh
```

Both install to `/opt/meo-3` (program files), `/etc/meo-3` (config — dpkg keeps your edits as conffiles, `install.sh` leaves a new version as `*.dist`), `/var/lib/meo-3` (data), `/usr/share/meo-3` (branding + flows template), plus the three systemd units and `/usr/bin/meo-3`. `apt purge` or `sudo meo-3/bin/uninstall.sh [--purge]` reverses it, including the generated `node_modules`.

Without root or systemd the tree also runs in place: `meo-3/bin/meo-3 start` spawns the three processes and logs to `meo-3/run/`.

## Known constraints

- **Install needs network**, running afterwards does not — Node-RED's dependencies are resolved at install time. Offline gateways need a baked-in `node_modules`.
- **The JRE dependency is derived, not hardcoded.** `stage.sh` records the service's bytecode version in `BUILD_INFO` and `deb.sh` turns it into `Depends: openjdk-<n>-jre-headless`. A JDK-21 build therefore requires openjdk-21, which **Debian 12 / Raspberry Pi OS Bookworm do not ship at all**, not even in backports. Those gateways need a JDK-17 rebuild, Debian 13, or a third-party JDK.
- **Broker must be on the gateway.** The Rust BLE service hardcodes `localhost:1883` and `meo-gateway` derives `mqtt://<host>:1883`; neither is configurable.
- **BLE binaries must be cross-built.** A host `cargo build` on a modern distro links a glibc newer than the gateways have, and the binary then refuses to start. `make dist` uses `cross` for both arches, and `stage.sh` fails the build if a binary's glibc floor exceeds `GLIBC_FLOOR` (2.36, Bookworm).
- **Firmware is not packaged.** `meo-arduino` ships to devices via PlatformIO.

Cutting a release: see [RELEASE.md](RELEASE.md).
