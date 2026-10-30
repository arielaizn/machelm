#!/bin/bash
# Builds MacHelm.app and a drag-to-install DMG.
#   scripts/build.sh            -> build/MacHelm.app and build/MacHelm-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
APP="build/MacHelm.app"
DMG="build/MacHelm-$VERSION.dmg"

# Command Line Tools ship SwiftUI's macro plugin only in the 26.x SDK; prefer it when present.
SDK_OVERRIDE="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ -d "$SDK_OVERRIDE" ] && ! xcode-select -p | grep -q "Xcode"; then
  export SDKROOT="$SDK_OVERRIDE"
fi

echo "▸ Compiling (release, universal)…"
ARCHS=()
for arch in arm64 x86_64; do
  if swift build -c release --arch "$arch" --scratch-path ".build-$arch" >/dev/null 2>&1; then ARCHS+=("$arch"); else echo "  (skipping $arch)"; fi
done
[ ${#ARCHS[@]} -gt 0 ] || { echo "build failed"; swift build -c release; exit 1; }

rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BINS=(); for a in "${ARCHS[@]}"; do BINS+=("$(swift build -c release --arch "$a" --scratch-path ".build-$a" --show-bin-path)/MacHelm"); done
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/MacHelm"
sed "s/__VERSION__/$VERSION/g" packaging/Info.plist > "$APP/Contents/Info.plist"

echo "▸ Generating icon & artwork…"
mkdir -p build/assets
if [ ! -f build/assets/AppIcon.iconset/icon_512x512@2x.png ]; then swift scripts/make_assets.swift build/assets; fi
iconutil -c icns build/assets/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "▸ Building DMG…"
PRE_INSTALLED=0; [ -e /Applications/MacHelm.app ] && PRE_INSTALLED=1
rm -f "$DMG" build/rw.dmg
STAGE="build/dmg-stage"; rm -rf "$STAGE"; mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp build/assets/dmg-background.png "$STAGE/.background/bg.png"
hdiutil create -volname "MacHelm" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov build/rw.dmg >/dev/null
DEV=$(hdiutil attach -readwrite -noverify -noautoopen build/rw.dmg | awk '/Apple_HFS/ {print $1; exit}')
sleep 2
# Lay out the window (best effort — needs Finder automation; the DMG is valid without it).
osascript <<OSA >/dev/null 2>&1 || echo "  (Finder layout skipped)"
tell application "Finder"
  tell disk "MacHelm"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set background picture of opts to file ".background:bg.png"
    set position of item "MacHelm.app" of container window to {170, 200}
    set position of item "Applications" of container window to {490, 200}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
OSA
# Finder sometimes drops a copy of the app into /Applications while laying out the window; undo that.
if [ "$PRE_INSTALLED" = 0 ]; then pkill -f /Applications/MacHelm.app 2>/dev/null || true; rm -rf /Applications/MacHelm.app; fi
sync
hdiutil detach "$DEV" >/dev/null || { sleep 2; hdiutil detach "$DEV" -force >/dev/null; }
hdiutil convert build/rw.dmg -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f build/rw.dmg
echo "✔ $APP"
echo "✔ $DMG ($(du -h "$DMG" | cut -f1))"
