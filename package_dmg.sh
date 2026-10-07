#!/bin/bash
# Packages build/Flame Sysconfig Setup.app into a drag-to-Applications disk image:
# build/Flame-Sysconfig-Setup-<version>.dmg (builds the app first if it isn't there).
#   NOTARY_PROFILE=<name>  also notarize and staple. Needs an app built with SIGN_IDENTITY (see build.sh), and
#                          credentials saved with `xcrun notarytool store-credentials <name>`.
set -euo pipefail
cd "$(dirname "$0")"

NAME="Flame Sysconfig Setup"
APP="build/$NAME.app"
[ -d "$APP" ] || ./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/Flame-Sysconfig-Setup-$VERSION.dmg"

# Stage and create the image on local disk: hdiutil is unreliable on network storage, and such volumes
# add extended attributes that would invalidate the signature.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STAGED="$WORK/stage/$NAME.app"
mkdir -p "$WORK/stage"
ditto --norsrc --noextattr --noqtn "$APP" "$STAGED"
codesign --verify --strict --verbose=1 "$STAGED"
ln -s /Applications "$WORK/stage/Applications"

make_image() {
  rm -f "$WORK/out.dmg"
  hdiutil create -quiet -volname "$NAME $VERSION" -srcfolder "$WORK/stage" -fs HFS+ -format UDZO "$WORK/out.dmg"
}
make_image

if [ -n "${NOTARY_PROFILE:-}" ]; then
  # Apple's queue can take hours; --wait sits there until it has an answer.
  xcrun notarytool submit "$WORK/out.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  # Staple the app, then rebuild the image around it: a copy dragged out of the image then validates
  # with no network, and keeps its ticket wherever it is copied afterwards.
  xcrun stapler staple "$STAGED"
  xcrun stapler validate "$STAGED"
  spctl --assess --type execute -vvv "$STAGED"
  make_image
  # Keep the stapled app in build/ too.
  rm -rf "$APP"
  ditto --norsrc --noextattr --noqtn "$STAGED" "$APP"
fi

rm -f "$DMG"
cp "$WORK/out.dmg" "$DMG"
(cd build && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Packaged $DMG ($(du -h "$DMG" | cut -f1))"
