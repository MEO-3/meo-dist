# Release packaging for the whole MEO 3 gateway (Java service + Rust BLE + Node-RED).
#
# This repo owns no source: it builds the sibling repos, stages their artifacts
# into one tree, and tars it. Sibling repos are expected next to this one.

VERSION  := $(shell cat VERSION)
ARCH     ?= $(shell uname -m | sed 's/^x86_64$$/x86_64/; s/^aarch64$$/arm64/')

SERVICE_DIR  ?= ../meo-edge
NODERED_DIR  ?= ../node-red-meo

STAGE := build/stage
DIST  := build/dist

.PHONY: help build-service build-ble build-node-red build stage dist dist-x86_64 dist-arm64 \
        package deb deb-full deb-x86_64 deb-arm64 clean

help:
	@echo "MEO 3 gateway packaging (version $(VERSION), arch $(ARCH))"
	@echo ""
	@echo "  make dist            Build everything for ARCH and package it"
	@echo "  make dist-x86_64     Package the linux-x86_64 bundle"
	@echo "  make dist-arm64      Package the linux-arm64 bundle (cross-built BLE)"
	@echo "  make package         Tar the staged tree (no component rebuild)"
	@echo "  make stage           Assemble build/stage/meo-3 without tarring"
	@echo ""
	@echo "  make deb             Build the .deb for ARCH from the staged tree"
	@echo "  make deb-x86_64      Build meo-3_<version>_amd64.deb"
	@echo "  make deb-arm64       Build meo-3_<version>_arm64.deb"
	@echo "  make clean           Remove build output"
	@echo ""
	@echo "  make build-service   gradlew installDist in $(SERVICE_DIR)"
	@echo "  make build-ble       Build the Rust BLE binary for ARCH"
	@echo "  make build-node-red  npm run release in $(NODERED_DIR)"
	@echo ""
	@echo "Output: $(DIST)/meo-3-$(VERSION)-linux-$(ARCH).tar.gz"

# --- component builds -------------------------------------------------------

# Gradle here fails on JDK 22+ before it even compiles, so check the build JDK
# rather than letting it die with a bare version number.
build-service:
	@jv=$$(java -version 2>&1 | head -1 | sed -n 's/.*version "\([0-9]*\).*/\1/p'); \
	if [ -z "$$jv" ] || [ "$$jv" -lt 17 ] || [ "$$jv" -gt 21 ]; then \
		echo "build JDK is $$jv; this build needs JDK 17-21." >&2; \
		echo "Set JAVA_HOME to a 17 or 21 JDK, e.g. JAVA_HOME=/usr/lib/jvm/java-21-openjdk make dist" >&2; \
		exit 1; \
	fi
	$(MAKE) -C $(SERVICE_DIR) build

# Both arches go through `cross`: a host build links this machine's glibc, which
# is newer than the gateways'. scripts/stage.sh enforces the floor.
build-ble:
ifeq ($(ARCH),arm64)
	$(MAKE) -C $(SERVICE_DIR) ble-arm
else
	$(MAKE) -C $(SERVICE_DIR) ble-x86-dist
endif

build-node-red:
	cd $(NODERED_DIR) && npm run release

build: build-service build-ble build-node-red

# --- staging & packaging ----------------------------------------------------

stage:
	ARCH=$(ARCH) VERSION=$(VERSION) SERVICE_DIR=$(SERVICE_DIR) \
	NODERED_DIR=$(NODERED_DIR) STAGE=$(STAGE) scripts/stage.sh

# package: tar the staged tree. dist: build the components first.
package: stage
	mkdir -p $(DIST)
	tar -czf $(DIST)/meo-3-$(VERSION)-linux-$(ARCH).tar.gz -C $(STAGE) meo-3
	@echo "packaged: $(DIST)/meo-3-$(VERSION)-linux-$(ARCH).tar.gz"

dist: build
	$(MAKE) ARCH=$(ARCH) package

dist-x86_64:
	$(MAKE) ARCH=x86_64 dist

dist-arm64:
	$(MAKE) ARCH=arm64 dist

deb: stage
	ARCH=$(ARCH) VERSION=$(VERSION) STAGE=$(STAGE) DIST=$(DIST) scripts/deb.sh

deb-full: build stage
	$(MAKE) ARCH=$(ARCH) deb

deb-x86_64:
	$(MAKE) ARCH=x86_64 deb

deb-arm64:
	$(MAKE) ARCH=arm64 deb

clean:
	rm -rf build
