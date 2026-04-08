PACKAGE_DIR := RustGoblin
SCHEME := RustGoblin
DERIVED_DATA := $(PACKAGE_DIR)/.build/XcodeDerivedData
ARCHIVE_PATH := $(PWD)/build/$(SCHEME).xcarchive
EXPORT_PATH := $(PWD)/build/export
APP_PROJECT := $(PACKAGE_DIR)/RustGoblin.xcodeproj
APP_SCHEME ?= RustGoblinApp
EXPORT_OPTIONS_PLIST ?= $(PWD)/AppStoreExportOptions.plist

.PHONY: build test run xcode-build archive clean appstore-export packaging-status

build:
	cd $(PACKAGE_DIR) && swift build

test:
	cd $(PACKAGE_DIR) && swift test

run:
	cd $(PACKAGE_DIR) && swift run

xcode-build:
	cd $(PACKAGE_DIR) && xcodebuild -scheme $(SCHEME) -destination 'platform=macOS' -configuration Debug build

archive:
	cd $(PACKAGE_DIR) && xcodebuild -scheme $(SCHEME) -destination 'platform=macOS' -configuration Release archive -archivePath $(ARCHIVE_PATH)

packaging-status:
	@echo "Current archive output is a universal binary under usr/local/bin inside the xcarchive."
	@echo "App Store export needs a dedicated macOS app target that produces a signed .app bundle."

appstore-export:
	@if [ ! -d "$(APP_PROJECT)" ]; then \
		echo "App Store export is blocked: $(APP_PROJECT) does not exist."; \
		echo "This repo currently archives a package executable, not an App Store-ready .app bundle."; \
		echo "Add a macOS app target that wraps the package sources, then rerun make appstore-export."; \
		exit 1; \
	fi
	@if [ ! -f "$(EXPORT_OPTIONS_PLIST)" ]; then \
		echo "Missing export options plist at $(EXPORT_OPTIONS_PLIST)."; \
		exit 1; \
	fi
	xcodebuild -project $(APP_PROJECT) -scheme $(APP_SCHEME) -destination 'platform=macOS' -configuration Release archive -archivePath $(ARCHIVE_PATH)
	xcodebuild -exportArchive -archivePath $(ARCHIVE_PATH) -exportPath $(EXPORT_PATH) -exportOptionsPlist $(EXPORT_OPTIONS_PLIST)

clean:
	rm -rf $(PACKAGE_DIR)/.build
	rm -rf $(PACKAGE_DIR)/.swiftpm/xcode
	rm -rf build
