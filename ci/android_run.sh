#!/bin/bash
# Внутри эмулятора: музыка на «телефон», проверка проверочной сборки, затем запуск обычной (подписанной) сборки
set -uo pipefail
MUSIC="$1"; DEBUG_APK="$2"; RELEASE_APK="$3"; OUT="$4"
mkdir -p "$OUT"
adb wait-for-device
# Память «телефона» готова не сразу после загрузки — ждём, пока в неё можно писать
for i in $(seq 1 60); do
  if adb shell 'mkdir -p /sdcard/Music && touch /sdcard/Music/.probe && rm /sdcard/Music/.probe' 2>/dev/null; then break; fi
  sleep 2
done
for f in "$MUSIC"/*.mp3; do
  for i in $(seq 1 10); do adb push "$f" /sdcard/Music/ && break; sleep 3; done
  adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file:///sdcard/Music/$(basename "$f")" > /dev/null 2>&1 || true
done
adb shell content call --uri content://media --method scan_volume --arg external_primary > /dev/null 2>&1 || true
# ждём, пока медиатека разберёт все три трека (на эмуляторе иногда приходится просить ещё раз)
scan_all() {
  for f in "$MUSIC"/*.mp3; do
    adb shell content call --uri content://media/external/file --method scan_file --arg "/storage/emulated/0/Music/$(basename "$f")" > /dev/null 2>&1 || true
  done
}
for i in $(seq 1 60); do
  N=$(adb shell content query --uri content://media/external/audio/media --projection title:is_music 2>/dev/null | grep -c "is_music=1")
  [ "${N:-0}" -ge 3 ] && break
  if [ $((i % 10)) = 1 ]; then scan_all; fi
  sleep 2
done
adb shell content query --uri content://media/external/audio/media --projection title:artist:is_music:duration || true
node ci/android_e2e.mjs "$DEBUG_APK" "$OUT"
RES=$?
# Обычная сборка: ставится и запускается
adb install -r -g "$RELEASE_APK" && adb shell am start -W -n ru.muzyka.offline/.MainActivity
sleep 8
adb exec-out screencap -p > "$OUT/12_release_build.png"
if adb shell pidof ru.muzyka.offline > /dev/null; then echo "PASS release build starts" | tee -a "$OUT/report.txt"; else echo "FAIL release build starts" | tee -a "$OUT/report.txt"; RES=1; fi
exit $RES
