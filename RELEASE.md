# Release process

How a MEO 3 release is cut. `<VERSION>` below is the version in `VERSION` (no `v` prefix); the git tag is `v<VERSION>`.

## 1. Prepare

- [ ] `VERSION` holds the version being released. Artifact names come from it, so it must match the tag: `VERSION` = `0.1.0` → tag `v0.1.0`.
- [ ] Sibling repos are committed and pushed — the release is built from their working trees, not from a tag, so anything uncommitted ships silently.
- [ ] Build host has JDK 17–21 (`make build-service` refuses anything else), Node.js >= 22.9, `cross`, and podman/docker.

## 2. Build all four artifacts

```bash
JAVA_HOME=/usr/lib/jvm/java-21-openjdk make dist-x86_64   # tarball + components
JAVA_HOME=/usr/lib/jvm/java-21-openjdk make dist-arm64
make ARCH=x86_64 deb
make ARCH=arm64 deb
sha256sum build/dist/* > build/dist/SHA256SUMS
```

Expected in `build/dist/`:

| file | |
| --- | --- |
| `meo-3-<VERSION>-linux-x86_64.tar.gz` | dev machines, any distro |
| `meo-3-<VERSION>-linux-arm64.tar.gz` | Pi / Nano Pi / NEO One |
| `meo-3_<VERSION>_amd64.deb` | Debian-family x86_64 |
| `meo-3_<VERSION>_arm64.deb` | Debian-family arm64 |
| `SHA256SUMS` | |

## 3. Verify before publishing

- [ ] `cat build/stage/meo-3/BUILD_INFO` — version, arch, and `java_runtime` are what you expect. `java_runtime` decides the deb's JRE dependency.
- [ ] Both BLE binaries are the right arch and stay under the glibc floor (`stage.sh` fails the build otherwise, but confirm it ran): `readelf -V <binary> | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1`
- [ ] Install both debs on real hardware or in a clean container, confirm the editor opens and a device appears, then `apt purge` and confirm it is clean.

## 4. Tag and publish

```bash
git tag -a v<VERSION> -m "MEO 3 v<VERSION>"
git push origin v<VERSION>
gh release create v<VERSION> build/dist/* \
    --title "MEO 3 v<VERSION>" \
    --notes-file <(release notes, from the template below)
```

Artifacts are attached to the GitHub release, not committed — `build/` is gitignored.

---

# Release notes template

Copy from here down, fill the placeholders, drop what does not apply.

---

## MEO 3 v\<VERSION\>

<!-- One sentence on what this release lets people do. -->

### What you can do

- Connect a MEO device over Bluetooth — no Wi-Fi setup on the device, no app.
- Watch live readings from sensors as they happen.
- Build automations by dragging blocks: when this changes, do that.
- Send commands to devices and see their replies.
- Everything runs on your own hardware. No account, no cloud, works offline once set up.

<!-- For later releases, replace the list above with what is new this time. -->

### Downloads

| file | for |
| --- | --- |
| `meo-3_<VERSION>_arm64.deb` | Raspberry Pi / Nano Pi / NEO One (Debian-family) |
| `meo-3_<VERSION>_amd64.deb` | x86_64 (Debian-family) |
| `meo-3-<VERSION>-linux-arm64.tar.gz` | arm64, any distro or no root |
| `meo-3-<VERSION>-linux-x86_64.tar.gz` | x86_64, any distro or no root |

Verify with `sha256sum -c SHA256SUMS`.

### Install

```bash
# Debian family
sudo apt install ./meo-3_<VERSION>_arm64.deb

# anywhere else, or without root
tar -xzf meo-3-<VERSION>-linux-arm64.tar.gz
sudo meo-3/bin/install.sh      # or: meo-3/bin/meo-3 start
```

Open `http://<address>:1880` and start building. Everything is preconfigured.

### Requirements

- **Node.js >= 22.9** — Debian 12 and Raspberry Pi OS Bookworm ship older, so add the NodeSource repository first: `curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install nodejs`
- **JRE \<N\>** — matches the JDK the service was built with; see `java_runtime` in `BUILD_INFO`.
- **mosquitto**
- **Network during install** — dependencies are resolved at install time.

### Known limitations

<!-- Keep only what is true for this release. -->

- Installing needs internet access; running afterwards does not.
- <!-- e.g. requires openjdk-21, which Raspberry Pi OS Bookworm does not provide -->

### Verified on

<!-- Be specific and honest: distro + arch + what was actually exercised. -->

- Debian 13 (trixie) amd64 — `apt install`, service starts, `apt purge` clean
- NEO One Armbian arm64 — `apt install`, service starts, `apt purge` clean
