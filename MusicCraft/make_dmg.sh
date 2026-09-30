#!/bin/bash
# Установщик для Mac: «Музыка в офлайн.dmg» (перетащить программу в «Программы»).
# Запуск после ./build.sh:  ./make_dmg.sh [папка-для-результата]
set -euo pipefail
cd "$(dirname "$0")"
NAME="Музыка в офлайн"
ROOT="$(cd .. && pwd)"
APP="$ROOT/$NAME.app"
[ -d "$APP" ] || { echo "Сначала соберите программу: ./build.sh"; exit 1; }
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="${1:-$ROOT/dist}"
mkdir -p "$OUT"
DMG="$OUT/Muzyka-v$VER-macOS.dmg"
T="$(mktemp -d)/dmg"
mkdir -p "$T"
ditto "$APP" "$T/$NAME.app"
ln -s /Applications "$T/Программы"
cat > "$T/Как открыть.txt" <<'TXT'
Музыка в офлайн — установка на Mac

1. Перетащи «Музыка в офлайн» на папку «Программы».
2. Открой «Программы» и дважды щёлкни по программе.
3. Если macOS пишет, что не может проверить разработчика:
   • macOS 15 и новее: «Системные настройки» → «Конфиденциальность и безопасность» →
     внизу «Всё равно открыть» → «Открыть».
   • macOS 14: щёлкни по программе правой кнопкой → «Открыть» → «Открыть».
   Это нужно один раз: программа не из App Store и без платной подписи Apple.

Нужна macOS 14 (Sonoma) или новее. Работает на Mac с Apple silicon и Intel.
TXT
rm -f "$DMG"
# hdiutil иногда отвечает «Resource busy» (система проверяет файлы) — пробуем ещё раз
for i in 1 2 3 4 5; do
  if hdiutil create -volname "$NAME" -srcfolder "$T" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null; then break; fi
  [ "$i" = 5 ] && exit 1
  echo "hdiutil занят, повтор через $((i * 5)) с…"; sleep $((i * 5))
done
rm -rf "$(dirname "$T")"
echo "✓ Готово: $DMG"
