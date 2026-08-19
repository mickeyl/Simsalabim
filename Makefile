prefix ?= $(HOME)/.local
INSTALL_DIR = $(prefix)/bin
NOTARY_PROFILE ?=

SUITE_CODESIGN_MATCH ?= Developer ID Application
SUITE_SIGN_IDENTITY := $(shell security find-identity -v -p codesigning | awk -F'"' '/$(SUITE_CODESIGN_MATCH)/ {print $$2; exit}')
SUITE_CODESIGN_FLAGS ?= --options runtime --timestamp
SUITE_SRCS = $(shell find Sources Modules/*/Sources/*-Mock \( -name '*.swift' -o -name '*.m' -o -name '*.h' \) -not -path '*/.build/*' 2>/dev/null)
SUITE_PLIST = Resources/Info.plist
SUITE_ENTITLEMENTS = Resources/entitlements.plist
SUITE_BUNDLE = Simsalabim.app
SUITE_BIN = $(SUITE_BUNDLE)/Contents/MacOS/Simsalabim
SUITE_BIN_NAME = Simsalabim
FONT_RESOURCE = Modules/ImpossiBLE/Sources/ImpossiBLE-Mock/ProviderKit/Resources/fa-brands-400.ttf
# Each module's own icon travels into the suite bundle so the sections can
# show their product branding. Missing files are skipped, not errors.
MODULE_ICONS = Modules/CAMouflage/Sources/CAMouflage-Mock/Resources/CAMouflage.icns \
               Modules/ImpossiBLE/Sources/ImpossiBLE-Mock/Resources/ImpossiBLE.icns
ICON_SOURCE = Assets/AppIcon.png
INSTALLED_APP = $(INSTALL_DIR)/$(SUITE_BUNDLE)
SUITE_DIST_ZIP = Simsalabim.zip

# Monotonic build number derived from commit count; falls back to the value
# already in the source Info.plist when the tree is not a git checkout.
BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null)

.DEFAULT_GOAL := help

.PHONY: help bootstrap check-pins suite suite-debug relaunch install uninstall run stop status log assess notarize clean

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
	@$(MAKE) --no-print-directory icon
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
	@$(MAKE) --no-print-directory icon
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

clean:
	rm -rf $(SUITE_BUNDLE) $(SUITE_DIST_ZIP)
