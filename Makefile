.PHONY: publish install release run clean

ifneq (,$(wildcard .env))
include .env
APPLE_ID := $(subst ",,$(APPLE_ID))
APPLE_TEAM_ID := $(subst ",,$(APPLE_TEAM_ID))
SIGNING_IDENTITY := $(subst ",,$(SIGNING_IDENTITY))
RELEASE_SIGNING_IDENTITY := $(subst ",,$(RELEASE_SIGNING_IDENTITY))
APP_PASSWORD := $(subst ",,$(APP_PASSWORD))
export APPLE_ID
export APPLE_TEAM_ID
export SIGNING_IDENTITY
export RELEASE_SIGNING_IDENTITY
export APP_PASSWORD
endif

APP_NAME = Crab Time
BUNDLE_ID = dev.crab.time
VERSION ?= 1.0.0
SWIFT_PACKAGE_DIR = CrabTime
SWIFT_BUILD_DIR = $(SWIFT_PACKAGE_DIR)/.build/release
EXECUTABLE_NAME = CrabTime
DIST_DIR = dist
APP_BUNDLE = $(DIST_DIR)/$(APP_NAME).app
DMG_PATH = $(DIST_DIR)/$(APP_NAME)-$(VERSION).dmg
OLD_APP_NAMES = RustGoblin Rot
CONTENTS_DIR = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources
RESOURCE_BUNDLE_NAME = $(EXECUTABLE_NAME)_$(EXECUTABLE_NAME).bundle
INSTALL_DIR ?= /Applications
INSTALL_APP_BUNDLE = $(INSTALL_DIR)/$(APP_NAME).app

define require_env
	@if [ -z "$($1)" ]; then \
		echo "Missing required setting: $1"; \
		exit 1; \
	fi
endef

publish:
	$(call require_env,APPLE_ID)
	$(call require_env,APPLE_TEAM_ID)
	$(call require_env,RELEASE_SIGNING_IDENTITY)
	$(call require_env,APP_PASSWORD)
	@echo "Building production release..."
	cd $(SWIFT_PACKAGE_DIR) && swift build -c release

	@echo "Assembling app bundle..."
	rm -rf "$(APP_BUNDLE)"
	@for name in $(OLD_APP_NAMES); do \
		rm -rf "$(DIST_DIR)/$$name.app"; \
		rm -f "$(DIST_DIR)/$$name-$(VERSION).dmg"; \
	done
	mkdir -p "$(MACOS_DIR)"
	mkdir -p "$(RESOURCES_DIR)"

	@echo "Copying executable..."
	cp "$(SWIFT_BUILD_DIR)/$(EXECUTABLE_NAME)" "$(MACOS_DIR)/$(EXECUTABLE_NAME)"
	chmod +x "$(MACOS_DIR)/$(EXECUTABLE_NAME)"

	@echo "Copying SwiftPM resources..."
	@if [ -d "$(SWIFT_BUILD_DIR)/$(RESOURCE_BUNDLE_NAME)" ]; then \
		ditto "$(SWIFT_BUILD_DIR)/$(RESOURCE_BUNDLE_NAME)" "$(RESOURCES_DIR)/$(RESOURCE_BUNDLE_NAME)"; \
	else \
		echo "No SwiftPM resource bundle found; continuing without it."; \
	fi

	@echo "Generating Info.plist..."
	@printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'    <key>CFBundleExecutable</key>' \
		'    <string>$(EXECUTABLE_NAME)</string>' \
		'    <key>CFBundleIdentifier</key>' \
		'    <string>$(BUNDLE_ID)</string>' \
		'    <key>CFBundleDisplayName</key>' \
		'    <string>$(APP_NAME)</string>' \
		'    <key>CFBundleName</key>' \
		'    <string>$(APP_NAME)</string>' \
		'    <key>CFBundlePackageType</key>' \
		'    <string>APPL</string>' \
		'    <key>CFBundleVersion</key>' \
		'    <string>$(VERSION)</string>' \
		'    <key>CFBundleShortVersionString</key>' \
		'    <string>$(VERSION)</string>' \
		'    <key>LSMinimumSystemVersion</key>' \
		'    <string>14.0.0</string>' \
		'    <key>NSHighResolutionCapable</key>' \
		'    <true/>' \
		'</dict>' \
		'</plist>' \
		> "$(CONTENTS_DIR)/Info.plist"

	@echo "Attaching icon if icon.png exists..."
	@if [ -f icon.png ]; then \
		mkdir -p "$(RESOURCES_DIR)/AppIcon.iconset"; \
		sips -z 16 16 icon.png --out "$(RESOURCES_DIR)/AppIcon.iconset/icon_16x16.png" >/dev/null; \
		sips -z 32 32 icon.png --out "$(RESOURCES_DIR)/AppIcon.iconset/icon_16x16@2x.png" >/dev/null; \
		sips -z 32 32 icon.png --out "$(RESOURCES_DIR)/AppIcon.iconset/icon_32x32.png" >/dev/null; \
		sips -z 64 64 icon.png --out "$(RESOURCES_DIR)/AppIcon.iconset/icon_32x32@2x.png" >/dev/null; \
		sips -z 128 128 icon.png --out "$(RESOURCES_DIR)/AppIcon.iconset/icon_128x128.png" >/dev/null; \
		sips -z 256 256 icon.png --out "$(RESOURCES_DIR)/AppIcon.iconset/icon_128x128@2x.png" >/dev/null; \
		sips -z 256 256 icon.png --out "$(RESOURCES_DIR)/AppIcon.iconset/icon_256x256.png" >/dev/null; \
		sips -z 512 512 icon.png --out "$(RESOURCES_DIR)/AppIcon.iconset/icon_256x256@2x.png" >/dev/null; \
		sips -z 512 512 icon.png --out "$(RESOURCES_DIR)/AppIcon.iconset/icon_512x512.png" >/dev/null; \
		sips -z 1024 1024 icon.png --out "$(RESOURCES_DIR)/AppIcon.iconset/icon_512x512@2x.png" >/dev/null; \
		iconutil -c icns "$(RESOURCES_DIR)/AppIcon.iconset" >/dev/null; \
		rm -rf "$(RESOURCES_DIR)/AppIcon.iconset"; \
		plutil -insert CFBundleIconFile -string AppIcon "$(CONTENTS_DIR)/Info.plist"; \
	else \
		echo "icon.png not found; skipping icon generation."; \
	fi

	@echo "Signing app bundle..."
	codesign --force --deep --options runtime --timestamp --sign "$(RELEASE_SIGNING_IDENTITY)" "$(APP_BUNDLE)"
	codesign --verify --deep --strict --verbose=2 "$(APP_BUNDLE)"

	@echo "Creating DMG..."
	rm -f "$(DMG_PATH)"
	@tmpdir=$$(mktemp -d); \
		cp -R "$(APP_BUNDLE)" "$$tmpdir/$(APP_NAME).app"; \
		ln -s /Applications "$$tmpdir/Applications"; \
		hdiutil create -volname "$(APP_NAME)" -srcfolder "$$tmpdir" -ov -format UDZO "$(DMG_PATH)" >/dev/null; \
		rm -rf "$$tmpdir"

	@echo "Submitting DMG for notarization..."
	xcrun notarytool submit "$(DMG_PATH)" \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(APPLE_TEAM_ID)" \
		--password "$(APP_PASSWORD)" \
		--wait

	@echo "Stapling notarization ticket to DMG..."
	xcrun stapler staple "$(DMG_PATH)"

	@echo "Validating signed app and notarized DMG..."
	spctl -a -vv "$(APP_BUNDLE)"
	xcrun stapler validate "$(DMG_PATH)"

	@echo "Published app bundle: $(APP_BUNDLE)"
	@echo "Published notarized DMG: $(DMG_PATH)"

install: publish
	@echo "Installing app bundle into $(INSTALL_DIR)..."
	mkdir -p "$(INSTALL_DIR)"
	@for name in $(OLD_APP_NAMES); do \
		rm -rf "$(INSTALL_DIR)/$$name.app"; \
	done
	rm -rf "$(INSTALL_APP_BUNDLE)"
	ditto "$(APP_BUNDLE)" "$(INSTALL_APP_BUNDLE)"
	@echo "Installed: $(INSTALL_APP_BUNDLE)"

release: publish

run:
	cd $(SWIFT_PACKAGE_DIR) && swift run

clean:
	cd $(SWIFT_PACKAGE_DIR) && swift package clean
	rm -rf "$(DIST_DIR)"
