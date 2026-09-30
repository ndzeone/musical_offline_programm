#!/bin/bash
# Сборка «Музыка в офлайн.app». Запуск: ./build.sh
# Для всех Mac сразу (Apple silicon и Intel): ARCHS="arm64 x86_64" ./build.sh
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
ARCH="$(uname -m)"
ARCHS="${ARCHS:-$ARCH}"
VERSION="2.3.0"
BUILD="5"
NAME="Музыка в офлайн"
EXEC="MuzykaOffline"
ROOT="$(cd .. && pwd)"
APP="$ROOT/$NAME.app"
B="build"
# Собираем во временной папке без «.app» и переносим на место уже готовую программу.
# Иначе Finder успевает записать в систему недособранную копию, и macOS потом отказывается
# её открывать («Не удаётся открыть программу», ошибка -10810).
S="$B/stage"
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

rm -rf "$B"
mkdir -p "$S/Contents/MacOS" "$S/Contents/Resources" "$B/icon.iconset"

echo "→ Компиляция ($ARCHS)…"
BINS=()
for A in $ARCHS; do
  swiftc -O -swift-version 5 -parse-as-library -target "$A-apple-macos14.0" \
    Sources/*.swift -o "$B/$EXEC-$A"
  BINS+=("$B/$EXEC-$A")
done
if [ ${#BINS[@]} -gt 1 ]; then lipo -create "${BINS[@]}" -output "$S/Contents/MacOS/$EXEC"; else cp "${BINS[0]}" "$S/Contents/MacOS/$EXEC"; fi

echo "→ Иконка…"
swiftc -O -swift-version 5 -target "$ARCH-apple-macos14.0" Sources/ArtKit.swift Tools/main.swift -o "$B/makeicon"
"$B/makeicon" "$B/icon.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$B/icon.png" --out "$B/icon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$B/icon.png" --out "$B/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$B/icon.iconset" -o "$S/Contents/Resources/AppIcon.icns"

cp Resources/*.ttf "$S/Contents/Resources/"
cat > "$S/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>local.musiccraft.player</string>
  <key>CFBundleExecutable</key><string>$EXEC</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Audio</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.audio</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

rm -rf "$APP"
mv "$S" "$APP"
codesign --force --sign - "$APP" >/dev/null 2>&1
# Старая версия под прежним названием больше не нужна — убираем и её запись в системе
rm -rf "$ROOT/MusicCraft.app"
"$LSREG" -u "$ROOT/MusicCraft.app" >/dev/null 2>&1 || true
# Заново регистрируем готовую программу, чтобы macOS не держалась за старую запись
"$LSREG" -f "$APP" >/dev/null 2>&1 || true
echo "✓ Готово: $APP"
