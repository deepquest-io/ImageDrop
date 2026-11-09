#!/usr/bin/env bash
# ImageDrop by deepquest | https://deepquest.code511.com/blog
# Builds ImageDrop.app into ./dist
#   bash build.sh               native build (Apple Silicon or Intel)
#   bash build.sh --universal   arm64 + x86_64 in one binary
#   bash build.sh --install     also copy the app to /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ImageDrop"
BUNDLE_ID="com.code511.deepquest.imagedrop"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(tr -d '[:space:]' < BUILD)"
UNIVERSAL=0
INSTALL=0

for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --install)   INSTALL=1 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift toolchain not found. Install Xcode, or run:  xcode-select --install"
  exit 1
fi

echo "▸ Building $APP_NAME v$VERSION (build $BUILD_NUMBER)… first build downloads and compiles libwebp, give it a minute."
if [[ $UNIVERSAL == 1 ]]; then
  swift build -c release --arch arm64
  swift build -c release --arch x86_64
  ARM_BIN="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"
  X86_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/$APP_NAME"
  mkdir -p .build/universal
  lipo -create "$ARM_BIN" "$X86_BIN" -output ".build/universal/$APP_NAME"
  BIN=".build/universal/$APP_NAME"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/$APP_NAME"
fi

# App icon: use Resources/AppIcon.icns if present, otherwise draw it from source.
make_icon() {
  local tmp set s d
  tmp="$(mktemp -d)"
  swift tools/make-icon.swift "$tmp/icon_1024.png" || return 1
  set="$tmp/AppIcon.iconset"
  mkdir -p "$set"
  for s in 16 32 128 256 512; do
    d=$((s * 2))
    sips -z "$s" "$s" "$tmp/icon_1024.png" --out "$set/icon_${s}x${s}.png" >/dev/null || return 1
    sips -z "$d" "$d" "$tmp/icon_1024.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null || return 1
  done
  mkdir -p Resources
  iconutil -c icns "$set" -o Resources/AppIcon.icns || return 1
  rm -rf "$tmp"
}
if [[ ! -f Resources/AppIcon.icns ]]; then
  echo "▸ Generating app icon"
  make_icon || echo "  (couldn't generate the icon; building with the default icon)"
fi

APP="dist/$APP_NAME.app"
echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>         <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>          <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>          <string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key>         <string>APPL</string>
  <key>CFBundleShortVersionString</key>  <string>$VERSION</string>
  <key>CFBundleVersion</key>             <string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key>            <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>      <string>13.0</string>
  <key>LSApplicationCategoryType</key>   <string>public.app-category.graphics-design</string>
  <key>NSHighResolutionCapable</key>     <true/>
  <key>NSPrincipalClass</key>            <string>NSApplication</string>
  <key>NSHumanReadableCopyright</key>    <string>© 2026 deepquest · https://deepquest.code511.com/blog</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>        <string>Image</string>
      <key>CFBundleTypeRole</key>        <string>Viewer</string>
      <key>LSHandlerRank</key>           <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.image</string>
        <string>public.folder</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS runs it without complaint on this Mac.
codesign --force --sign - "$APP" >/dev/null

if [[ $INSTALL == 1 ]]; then
  echo "▸ Installing to /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  APP="/Applications/$APP_NAME.app"
fi

echo "✓ Done: $APP  (v$VERSION, build $BUILD_NUMBER)"
echo "  Open it with:  open \"$APP\""
