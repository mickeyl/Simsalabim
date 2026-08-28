prefix ?= $(HOME)/.local
INSTALL_DIR = $(prefix)/bin
NOTARY_PROFILE ?=

SUITE_CODESIGN_MATCH ?= Developer ID Application
SUITE_SIGN_IDENTITY := $(shell security find-identity -v -p codesigning | awk -F'"' '/$(SUITE_CODESIGN_MATCH)/ {print $$2; exit}')
SUITE_CODESIGN_FLAGS ?= --options runtime --timestamp
SUITE_SRCS = $(shell find Sources Modules/*/Sources/*-Mac \( -name '*.swift' -o -name '*.m' -o -name '*.h' \) -not -path '*/.build/*' 2>/dev/null)
SUITE_PLIST = Resources/Info.plist
SUITE_ENTITLEMENTS = Resources/entitlements.plist
SUITE_BUNDLE = Simsalabim.app
SUITE_BIN = $(SUITE_BUNDLE)/Contents/MacOS/Simsalabim
SUITE_BIN_NAME = Simsalabim
FONT_RESOURCE = Modules/ImpossiBLE/Sources/ImpossiBLE-Mac/ProviderKit/Resources/fa-brands-400.ttf
# Each module's own icon travels into the suite bundle so the sections can
# show their product branding. Missing files are skipped, not errors.
MODULE_ICONS = Modules/CAMouflage/Sources/CAMouflage-Mac/Resources/CAMouflage.icns \
               Modules/ImpossiBLE/Sources/ImpossiBLE-Mac/Resources/ImpossiBLE.icns \
               Modules/NFCromancer/Sources/NFCromancer-Mac/Resources/NFCromancer.icns
ICON_SOURCE = Assets/AppIcon.png
INSTALLED_APP = $(INSTALL_DIR)/$(SUITE_BUNDLE)
SUITE_DIST_ZIP = Simsalabim.zip

# The headless CLI ships as a bare binary, not an app bundle — SeedRunner
# resolves SeedAgent.app/Fixtures via Bundle.main.resourceURL, which for a
# bare SwiftPM executable is just the directory next to it, so both are
# staged alongside the binary (here, and again next to it in $(INSTALL_DIR)).
CLI_BIN_NAME = simsalabim
CLI_STAGE_DIR = simsalabim-cli
CLI_BIN = $(CLI_STAGE_DIR)/$(CLI_BIN_NAME)
CLI_MAN_SRC = Man/simsalabim.1
MAN_INSTALL_DIR = $(prefix)/share/man/man1

# SeedAgent (Simulacrum's simulator-installed app) ships as a bundled
# resource, same as the module icons above — one suite build produces a
# host app that can seed on its own. Cross-compiled for the iOS Simulator
# SDK straight from the submodule checkout; ad hoc signing is sufficient
# for `simctl install` (see Modules/Simulacrum/Makefile's own `agent`
# target, which this mirrors).
AGENT_DIR = Modules/Simulacrum
AGENT_SDK := $(shell xcrun --sdk iphonesimulator --show-sdk-path)
AGENT_TRIPLE ?= arm64-apple-ios17.0-simulator
AGENT_APP = $(AGENT_DIR)/SeedAgent.app
FIXTURE_PHOTOS_SOURCE = $(AGENT_DIR)/Sources/Simulacrum-Mac/Resources/Fixtures

# Monotonic build number derived from commit count; falls back to the value
# already in the source Info.plist when the tree is not a git checkout.
BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null)

.DEFAULT_GOAL := help

.PHONY: help bootstrap check-pins suite suite-debug relaunch install uninstall run stop status log assess notarize clean bundle-agent agent-clean cli cli-install cli-uninstall

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Suite app (all simulator-retrofitting providers, one menu bar item):"
	@echo "  bootstrap   Initialize/update the product submodules"
	@echo "  check-pins  Verify submodule pins are reachable on their origin/master"
	@echo "  suite       Build Simsalabim.app (release)"
	@echo "  suite-debug Build with debug symbols"
	@echo "  relaunch    Quick debug rebuild and background relaunch"
	@echo "  run         Install and start the suite app"
	@echo "  stop        Stop the running suite app"
	@echo "  status      Show whether the suite app is running"
	@echo "  log         Tail system log output from the suite app"
	@echo "  assess      Verify signing and Gatekeeper assessment"
	@echo "  notarize    Notarize the suite app (requires NOTARY_PROFILE)"
	@echo "  install     Build and install to \$$(prefix)/bin  [$(prefix)]"
	@echo "  uninstall   Remove installed files from \$$(prefix)/bin"
	@echo "  clean       Remove build artifacts"
	@echo ""
	@echo "Headless CLI (drives a running Simsalabim.app, and can seed on its own):"
	@echo "  cli           Build the simsalabim binary into $(CLI_STAGE_DIR)/"
	@echo "  cli-install   Build and install to \$$(prefix)/bin, with its man page  [$(prefix)]"
	@echo "  cli-uninstall Remove the installed CLI binary and man page"
	@echo ""
	@echo "Variables:"
	@echo "  SUITE_CODESIGN_MATCH  Signing identity  [$(SUITE_CODESIGN_MATCH)]"
	@echo "  NOTARY_PROFILE        notarytool profile [$(NOTARY_PROFILE)]"

bootstrap:
	git submodule update --init
	@echo "Submodules ready"

check-pins:
	@ok=1; for module in Modules/*/; do \
		git -C $$module fetch -q origin; \
		pin=$$(git -C $$module rev-parse HEAD); \
		if git -C $$module merge-base --is-ancestor $$pin origin/master; then \
			echo "OK    $$module ($$(git -C $$module rev-parse --short HEAD))"; \
		else \
			echo "STALE $$module pin $$pin is not on origin/master"; ok=0; \
		fi; \
	done; [ $$ok -eq 1 ]

SWIFTPM_FLAGS ?= --disable-sandbox

suite: $(SUITE_BIN)

suite-debug:
	@mkdir -p $(SUITE_BUNDLE)/Contents/MacOS $(SUITE_BUNDLE)/Contents/Resources
	@cp $(SUITE_PLIST) $(SUITE_BUNDLE)/Contents/Info.plist
	@if [ -n "$(BUILD_NUMBER)" ]; then /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" $(SUITE_BUNDLE)/Contents/Info.plist; fi
	swift build $(SWIFTPM_FLAGS)
	@cp $$(swift build $(SWIFTPM_FLAGS) --show-bin-path)/$(SUITE_BIN_NAME) $(SUITE_BIN)
	@cp $(FONT_RESOURCE) $(SUITE_BUNDLE)/Contents/Resources/
	@for icon in $(MODULE_ICONS); do [ -f "$$icon" ] && cp "$$icon" $(SUITE_BUNDLE)/Contents/Resources/ || true; done
	@$(MAKE) --no-print-directory icon bundle-agent
	@codesign --force --sign - --entitlements $(SUITE_ENTITLEMENTS) $(SUITE_BUNDLE) >/dev/null
	@xattr -cr $(SUITE_BUNDLE) 2>/dev/null || true

relaunch: suite-debug
	@pkill -f "$(SUITE_BIN_NAME).app/Contents/MacOS" 2>/dev/null && sleep 0.5 || true
	@open "$(SUITE_BUNDLE)"
	@echo "Simsalabim relaunched (debug build)"

$(SUITE_BIN): $(SUITE_SRCS) $(SUITE_PLIST) $(SUITE_ENTITLEMENTS)
	mkdir -p $(SUITE_BUNDLE)/Contents/MacOS $(SUITE_BUNDLE)/Contents/Resources
	cp $(SUITE_PLIST) $(SUITE_BUNDLE)/Contents/Info.plist
	@if [ -n "$(BUILD_NUMBER)" ]; then /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" $(SUITE_BUNDLE)/Contents/Info.plist; fi
	swift build $(SWIFTPM_FLAGS) -c release
	cp $$(swift build $(SWIFTPM_FLAGS) -c release --show-bin-path)/$(SUITE_BIN_NAME) $(SUITE_BIN)
	cp $(FONT_RESOURCE) $(SUITE_BUNDLE)/Contents/Resources/
	@for icon in $(MODULE_ICONS); do [ -f "$$icon" ] && cp "$$icon" $(SUITE_BUNDLE)/Contents/Resources/ || true; done
	@$(MAKE) --no-print-directory icon bundle-agent
	@if [ -z "$(SUITE_SIGN_IDENTITY)" ]; then \
		echo "WARNING: No codesigning identity matching '$(SUITE_CODESIGN_MATCH)' found in your keychain."; \
		echo "Signing the suite app ad hoc. Gatekeeper will reject quarantined or distributed copies."; \
		codesign --force --sign - --entitlements $(SUITE_ENTITLEMENTS) $(SUITE_BUNDLE); \
	else \
		echo "Codesigning suite app with: $(SUITE_SIGN_IDENTITY)"; \
		codesign --force --sign "$(SUITE_SIGN_IDENTITY)" $(SUITE_CODESIGN_FLAGS) --entitlements $(SUITE_ENTITLEMENTS) $(SUITE_BUNDLE); \
	fi
	@xattr -cr $(SUITE_BUNDLE) 2>/dev/null || true

# Renders Assets/AppIcon.png into the bundle's AppIcon.icns. A missing source
# image is not an error — the bundle just ships without a custom icon.
.PHONY: icon
icon:
	@if [ -f "$(ICON_SOURCE)" ]; then \
		rm -rf /tmp/simsalabim-icon.iconset; \
		mkdir -p /tmp/simsalabim-icon.iconset; \
		for size in 16 32 128 256 512; do \
			sips -z $$size $$size "$(ICON_SOURCE)" --out /tmp/simsalabim-icon.iconset/icon_$${size}x$${size}.png >/dev/null; \
			sips -z $$((size*2)) $$((size*2)) "$(ICON_SOURCE)" --out /tmp/simsalabim-icon.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
		done; \
		iconutil -c icns /tmp/simsalabim-icon.iconset -o $(SUITE_BUNDLE)/Contents/Resources/AppIcon.icns; \
		rm -rf /tmp/simsalabim-icon.iconset; \
	fi

# Cross-compiles SeedAgent for the iOS Simulator SDK from the Simulacrum
# submodule and copies the ad-hoc-signed .app plus its fixture photo
# swatches into the suite bundle's Resources — SeedRunner (inside
# SimulacrumProviderKit) finds both via Bundle.main.resourceURL, whichever
# host app it's running in.
$(AGENT_APP):
	@cd $(AGENT_DIR) && swift build $(SWIFTPM_FLAGS) --sdk $(AGENT_SDK) --triple $(AGENT_TRIPLE) 2>&1 | tail -3
	@rm -rf $(AGENT_APP)
	@mkdir -p $(AGENT_APP)
	@cp $$(cd $(AGENT_DIR) && swift build $(SWIFTPM_FLAGS) --sdk $(AGENT_SDK) --triple $(AGENT_TRIPLE) --show-bin-path)/SeedAgent $(AGENT_APP)/SeedAgent
	@cp $(AGENT_DIR)/Sources/SeedAgent/Resources/Info.plist $(AGENT_APP)/Info.plist
	@codesign --force --sign - $(AGENT_APP) >/dev/null

bundle-agent: $(AGENT_APP)
	@mkdir -p $(SUITE_BUNDLE)/Contents/Resources/Fixtures
	@rm -rf $(SUITE_BUNDLE)/Contents/Resources/SeedAgent.app
	@cp -R $(AGENT_APP) $(SUITE_BUNDLE)/Contents/Resources/SeedAgent.app
	@cp $(FIXTURE_PHOTOS_SOURCE)/*.png $(SUITE_BUNDLE)/Contents/Resources/Fixtures/ 2>/dev/null || true

agent-clean:
	rm -rf $(AGENT_APP)

cli: $(AGENT_APP)
	swift build $(SWIFTPM_FLAGS) -c release --product $(CLI_BIN_NAME)
	@mkdir -p $(CLI_STAGE_DIR)/Fixtures
	@cp $$(swift build $(SWIFTPM_FLAGS) -c release --show-bin-path)/$(CLI_BIN_NAME) $(CLI_BIN)
	@rm -rf $(CLI_STAGE_DIR)/SeedAgent.app
	@cp -R $(AGENT_APP) $(CLI_STAGE_DIR)/SeedAgent.app
	@cp $(FIXTURE_PHOTOS_SOURCE)/*.png $(CLI_STAGE_DIR)/Fixtures/ 2>/dev/null || true

cli-install: cli
	mkdir -p $(INSTALL_DIR)
	cp $(CLI_BIN) $(INSTALL_DIR)/$(CLI_BIN_NAME)
	rm -rf $(INSTALL_DIR)/SeedAgent.app $(INSTALL_DIR)/Fixtures
	cp -R $(CLI_STAGE_DIR)/SeedAgent.app $(INSTALL_DIR)/SeedAgent.app
	cp -R $(CLI_STAGE_DIR)/Fixtures $(INSTALL_DIR)/Fixtures
	mkdir -p $(MAN_INSTALL_DIR)
	cp $(CLI_MAN_SRC) $(MAN_INSTALL_DIR)/simsalabim.1
	@echo "Installed. Try: man simsalabim (add $(MAN_INSTALL_DIR) to \$$MANPATH if not already on it)"

cli-uninstall:
	rm -f $(INSTALL_DIR)/$(CLI_BIN_NAME) $(MAN_INSTALL_DIR)/simsalabim.1
	rm -rf $(INSTALL_DIR)/SeedAgent.app $(INSTALL_DIR)/Fixtures
	@echo "simsalabim CLI uninstalled from $(INSTALL_DIR)"

install: suite
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALLED_APP)
	cp -R $(SUITE_BUNDLE) $(INSTALL_DIR)/
	@xattr -cr $(INSTALLED_APP) 2>/dev/null || true

uninstall:
	rm -rf $(INSTALLED_APP)
	@echo "Uninstalled from $(INSTALL_DIR)"

run: install
	@if ! pgrep -f $(SUITE_BIN_NAME) > /dev/null 2>&1; then \
		open "$(INSTALLED_APP)"; \
		echo "Simsalabim started"; \
	else \
		echo "Simsalabim already running"; \
	fi

stop:
	@pid=$$(pgrep -f "$(SUITE_BIN_NAME).app/Contents/MacOS" 2>/dev/null); \
	if [ -n "$$pid" ]; then \
		kill "$$pid"; \
		echo "Simsalabim stopped (was PID $$pid)"; \
	else \
		echo "Simsalabim is not running"; \
	fi

status:
	@pid=$$(pgrep -f "$(SUITE_BIN_NAME).app/Contents/MacOS" 2>/dev/null); \
	if [ -n "$$pid" ]; then \
		echo "Simsalabim is running (PID $$pid)"; \
	else \
		echo "Simsalabim is not running"; \
	fi

log:
	@echo "Tailing logs for Simsalabim… (^C to stop)"
	@log stream --predicate 'process == "$(SUITE_BIN_NAME)"' --style compact

assess: suite
	codesign --verify --deep --strict --verbose=4 $(SUITE_BUNDLE)
	spctl -a -vvv -t exec $(SUITE_BUNDLE)

notarize:
	@if [ -z "$(NOTARY_PROFILE)" ]; then \
		echo "ERROR: Set NOTARY_PROFILE to a notarytool keychain profile."; \
		exit 1; \
	fi
	rm -rf $(SUITE_BUNDLE)
	$(MAKE) suite
	rm -f $(SUITE_DIST_ZIP)
	ditto -c -k --keepParent --sequesterRsrc --zlibCompressionLevel 9 $(SUITE_BUNDLE) $(SUITE_DIST_ZIP)
	xcrun notarytool submit $(SUITE_DIST_ZIP) --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(SUITE_BUNDLE)
	$(MAKE) assess

clean: agent-clean
	rm -rf $(SUITE_BUNDLE) $(SUITE_DIST_ZIP) $(CLI_STAGE_DIR)
