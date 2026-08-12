# Convenience wrapper over the scripts. See README.md.
.PHONY: all build install setup uninstall test vendor-cache verify clean distclean

all: build

build:                        ## build runtime and Link helper with Podman -> dist/
	./build.sh

install:                      ## install the built Wine tree + launcher (end user)
	./scripts/installer.sh install --skip-live-install

setup:                        ## create/refresh the Wine prefix (end user)
	./scripts/setup-prefix.sh

uninstall:                    ## remove installed Wine tree + launcher
	./scripts/installer.sh uninstall --keep-prefix

test:                         ## run installer and launcher lifecycle gates
	./scripts/test-shortcut-hold.sh
	./scripts/test-desktop-integration.sh
	./scripts/test-installer-lifecycle.sh

vendor-cache:                 ## populate vendor/winetricks-cache for offline setup
	./scripts/vendor-winetricks-cache.sh

verify:                       ## check vendored inputs against pinned checksums
	cd vendor && sha256sum -c wine-base.sha256 pipeasio.sha256 pipewire-sdk.sha256 ntsync-uapi.sha256 link.sha256

clean:                        ## remove build outputs
	rm -rf dist

distclean: clean              ## also drop the container image
	-$${ENGINE:-podman} rmi ableton-wine-build:22.04
