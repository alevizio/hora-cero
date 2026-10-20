#!/bin/bash
# Hora Cero launch videos from the takes: the score, the two edits and the light copy for WhatsApp.
# usage: horacero_finish.sh <takes dir (16:9)> <takes dir (9:16)> <out dir>
# The takes come from horacero_takes.sh (horacero_takes.txt: one horacero_run.sh run each).
set -e
wide=$1; up=$2; out=${3:-.}
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
mkdir -p "$out"
python3 "$here/horacero_music.py" "$tmp/wide.wav" wide
python3 "$here/horacero_music.py" "$tmp/upright.wav" upright
python3 "$here/compose_horacero.py" "$wide" "$out/Hora Cero - trailer 16x9.mp4" wide --music "$tmp/wide.wav"
python3 "$here/compose_horacero.py" "$up" "$out/Hora Cero - vertical 9x16 (Reels, TikTok, Stories).mp4" upright --music "$tmp/upright.wav"
# the light copy: 720p, two passes at a bitrate that keeps the whole film under 16 MB (WhatsApp)
src="$out/Hora Cero - trailer 16x9.mp4"
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src")
kbps=$(python3 -c "print(int(15.0 * 8192 / $dur - 128 - 40))")
ffmpeg -v error -y -i "$src" -vf scale=1280:720:flags=lanczos -c:v libx264 -preset slow -b:v ${kbps}k -pass 1 \
  -passlogfile "$tmp/pass" -an -f mp4 /dev/null
ffmpeg -v error -y -i "$src" -vf scale=1280:720:flags=lanczos -c:v libx264 -preset slow -b:v ${kbps}k -pass 2 \
  -passlogfile "$tmp/pass" -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "$out/Hora Cero - trailer 16x9 (WhatsApp, light).mp4"
rm -rf "$tmp"
ls -la "$out"
