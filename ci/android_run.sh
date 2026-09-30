#!/bin/bash
# Внутри эмулятора: музыка на «телефон», проверка проверочной сборки, затем запуск обычной (подписанной) сборки
set -uo pipefail
MUSIC="$1"; DEBUG_APK="$2"; RELEASE_APK="$3"; OUT="$4"
mkdir -p "$OUT"
adb wait-for-device
adb shell mkdir -p /sdcard/Music
adb push "$MUSIC"/*.mp3 /sdcard/Music/
for f in "$MUSIC"/*.mp3; do adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file:///sdcard/Music/$(basename "$f")" > /dev/null; done
adb shell content call --uri content://media --method scan_volume --arg external_primary > /dev/null 2>&1 || true
sleep 8
adb shell content query --uri content://media/external/audio/media --projection title:artist:is_music || true
node ci/android_e2e.mjs "$DEBUG_APK" "$OUT"
RES=$?
# Обычная сборка: ставится и запускается
adb install -r -g "$RELEASE_APK" && adb shell am start -W -n ru.muzyka.offline/.MainActivity
sleep 8
adb exec-out screencap -p > "$OUT/12_release_build.png"
if adb shell pidof ru.muzyka.offline > /dev/null; then echo "PASS release build starts" | tee -a "$OUT/report.txt"; else echo "FAIL release build starts" | tee -a "$OUT/report.txt"; RES=1; fi
exit $RES
