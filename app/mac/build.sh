#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
output_dir="${1:-$repo_dir/dist}"
app_dir="$output_dir/Display Handoff Setup.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources/mac" "$output_dir/swift-cache"
for arch in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -O -parse-as-library \
        -module-cache-path "$output_dir/swift-cache" -target "$arch-apple-macos13.0" \
        "$repo_dir/app/mac/SetupCore.swift" "$repo_dir/app/mac/SetupApp.swift" \
        -o "$output_dir/setup-$arch"
done
lipo -create "$output_dir/setup-arm64" "$output_dir/setup-x86_64" -output "$app_dir/Contents/MacOS/DisplayHandoffSetup"
cp "$repo_dir/mac/deskflow_keys.lua" "$repo_dir/mac/deskflow_mouse.lua" "$app_dir/Contents/Resources/mac/"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.deskflow-display-handoff.setup</string>
<key>CFBundleName</key><string>Display Handoff Setup</string>
<key>CFBundleExecutable</key><string>DisplayHandoffSetup</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
ditto -c -k --keepParent "$app_dir" "$output_dir/DisplayHandoffSetup-mac-universal.zip"
printf '%s\n' "$app_dir"
