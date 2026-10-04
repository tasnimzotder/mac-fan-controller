#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(cat VERSION)
configuration=${MFC_BUILD_CONFIGURATION:-release}
sign_identity=${MFC_SIGN_IDENTITY:--}
swift build -c "$configuration" --arch arm64 -Xswiftc -warnings-as-errors
binary_dir=$(swift build -c "$configuration" --arch arm64 --show-bin-path)
app="dist/Mac Fan Controller.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Library/LaunchDaemons"
cp "$binary_dir/mac-fan-controller" "$app/Contents/MacOS/"
cp "$binary_dir/mfc-helper" "$app/Contents/MacOS/"
if [ -f assets/AppIcon.icns ]; then cp assets/AppIcon.icns "$app/Contents/Resources/"; fi
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>mac-fan-controller</string>
<key>CFBundleIdentifier</key><string>com.tasnimzotder.mac-fan-controller</string>
<key>CFBundleName</key><string>Mac Fan Controller</string>
<key>CFBundleDisplayName</key><string>Mac Fan Controller</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>${version%%-*}</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp assets/com.tasnimzotder.mac-fan-controller.helper.plist "$app/Contents/Library/LaunchDaemons/"
plutil -lint "$app/Contents/Info.plist" "$app/Contents/Library/LaunchDaemons/"*.plist
codesign --force --options runtime --sign "$sign_identity" --identifier com.tasnimzotder.mac-fan-controller.helper "$app/Contents/MacOS/mfc-helper"
codesign --force --options runtime --sign "$sign_identity" "$app"
codesign --verify --deep --strict "$app"
echo "Built $app ($version, arm64)"
