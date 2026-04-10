.PHONY: release run clean

APP_NAME = RustGoblin
BUNDLE_ID = com.goldcoders.rustgoblin
VERSION = 1.0.0
BUILD_DIR = .build/release
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
MACOS_DIR = $(APP_BUNDLE)/Contents/MacOS
RESOURCES_DIR = $(APP_BUNDLE)/Contents/Resources

release:
	@echo "🚀 Building release binary..."
	cd RustGoblin && swift build -c release

	@echo "📦 Assembling app bundle..."
	mkdir -p $(MACOS_DIR)
	mkdir -p $(RESOURCES_DIR)

	@echo "📄 Copying executable..."
	cp RustGoblin/.build/release/RustGoblin $(MACOS_DIR)/

	@echo "📄 Generating Info.plist..."
	cat <<EOF > $(APP_BUNDLE)/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>RustGoblin</string>
    <key>CFBundleIdentifier</key>
    <string>$(BUNDLE_ID)</string>
    <key>CFBundleName</key>
    <string>$(APP_NAME)</string>
    <key>CFBundleVersion</key>
    <string>$(VERSION)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(VERSION)</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

	@echo "🎨 Generating placeholder icon..."
	mkdir -p $(RESOURCES_DIR)/AppIcon.iconset
	sips -z 16 16     icon.png --out $(RESOURCES_DIR)/AppIcon.iconset/icon_16x16.png || true
	sips -z 32 32     icon.png --out $(RESOURCES_DIR)/AppIcon.iconset/icon_16x16@2x.png || true
	sips -z 32 32     icon.png --out $(RESOURCES_DIR)/AppIcon.iconset/icon_32x32.png || true
	sips -z 64 64     icon.png --out $(RESOURCES_DIR)/AppIcon.iconset/icon_32x32@2x.png || true
	sips -z 128 128   icon.png --out $(RESOURCES_DIR)/AppIcon.iconset/icon_128x128.png || true
	sips -z 256 256   icon.png --out $(RESOURCES_DIR)/AppIcon.iconset/icon_128x128@2x.png || true
	sips -z 256 256   icon.png --out $(RESOURCES_DIR)/AppIcon.iconset/icon_256x256.png || true
	sips -z 512 512   icon.png --out $(RESOURCES_DIR)/AppIcon.iconset/icon_256x256@2x.png || true
	sips -z 512 512   icon.png --out $(RESOURCES_DIR)/AppIcon.iconset/icon_512x512.png || true
	sips -z 1024 1024 icon.png --out $(RESOURCES_DIR)/AppIcon.iconset/icon_512x512@2x.png || true
	iconutil -c icns $(RESOURCES_DIR)/AppIcon.iconset || true
	rm -rf $(RESOURCES_DIR)/AppIcon.iconset
	sed -i '' '/<dict>/a\'$'\n\\t<key>CFBundleIconFile</key>\n\t<string>AppIcon</string>' $(APP_BUNDLE)/Contents/Info.plist

	@echo "✅ App bundle created at $(APP_BUNDLE)"
	@echo "Note: To distribute, consider creating a DMG via tools like 'create-dmg'"

run:
	cd RustGoblin && swift run

clean:
	cd RustGoblin && swift package clean
	rm -rf $(BUILD_DIR)
