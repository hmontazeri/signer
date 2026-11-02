#!/bin/bash
# Baut Signer.app (braucht nur die Command Line Tools, kein Xcode)
set -e
cd "$(dirname "$0")"
mkdir -p build
swiftc -O -swift-version 5 -parse-as-library Sources/Signer/*.swift -o build/Signer-bin
APP=build/Signer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Icon: Resources/icon-1024.png -> AppIcon.icns (neu zeichnen: swiftc Resources/make-icon.swift -o /tmp/mi && /tmp/mi Resources/icon-1024.png)
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
cp build/Signer-bin "$APP/Contents/MacOS/Signer"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>de.montazeri.signer</string>
  <key>CFBundleName</key><string>Signer</string>
  <key>CFBundleDisplayName</key><string>PDF Signer</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>Signer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Damit du mit dem iPhone unterschreiben kannst.</string>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>PDF</string>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>LSItemContentTypes</key><array><string>com.adobe.pdf</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Fertig: $PWD/$APP"

# Installation: ./build.sh install  -> kopiert die App nach /Applications
if [ "$1" = "install" ]; then
  DEST=/Applications
  [ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
  pkill -x Signer 2>/dev/null || true
  rm -rf "$DEST/Signer.app"
  cp -R "$APP" "$DEST/Signer.app"
  echo "Installiert: $DEST/Signer.app"
fi
