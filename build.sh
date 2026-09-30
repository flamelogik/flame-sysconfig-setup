#!/bin/bash
# Builds "Flame Sysconfig Setup.app" (universal: Apple silicon + Intel, macOS 13+) into ./build
set -euo pipefail
cd "$(dirname "$0")"

NAME="Flame Sysconfig Setup"
VERSION="${VERSION:-1.0.0}"   # set from the git tag by the release workflow
BUILD="${BUILD:-1}"
EXE="SysconfigSetup"
TMP="$(mktemp -d)"
# Assemble and sign on local disk: network volumes (e.g. NEXIS) add metadata codesign rejects.
APP="$TMP/$NAME.app"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -swift-version 5 \
    -target "$arch-apple-macos13.0" \
    Sources/*.swift -o "$TMP/$EXE-$arch"
done
lipo -create "$TMP/$EXE-arm64" "$TMP/$EXE-x86_64" -output "$APP/Contents/MacOS/$EXE"

# The icon is generated once; delete Resources/AppIcon.icns to redraw it.
if [ ! -f Resources/AppIcon.icns ]; then
  mkdir -p Resources
  swift tools/make_icon.swift Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundleIdentifier</key><string>io.github.flamelogik.flame-sysconfig-setup</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"

mkdir -p build
rm -rf "build/$NAME.app"
ditto --norsrc --noextattr "$APP" "build/$NAME.app"
echo "Built build/$NAME.app"
