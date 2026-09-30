#!/bin/bash
# Три проверочных трека с тегами и обложкой (синус 30 с) для эмулятора
set -euo pipefail
OUT="$1"; ICON="$2"
mkdir -p "$OUT"
mk() { ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=$1:duration=30" -i "$ICON" -map 0:a -map 1:v -c:a libmp3lame -b:a 128k -c:v mjpeg -disposition:v attached_pic \
  -id3v2_version 3 -metadata title="$2" -metadata artist="$3" -metadata album="Проверка" "$OUT/$4.mp3"; }
mk 220 "Jingle Bells" "Frank Sinatra" track1
mk 330 "Второй трек" "Демо Исполнитель" track2
mk 440 "Третий трек" "Ещё кто-то" track3
# файл «в дальней папке»: его медиатека заранее не видит (проверка поиска всей музыки)
mkdir -p "$OUT/hidden"
mk 550 "Спрятанный трек" "Проверка" hidden/track4
ls -la "$OUT"
