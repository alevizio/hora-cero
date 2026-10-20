#!/bin/bash
# The Hora Cero gameplay demonstration (horacero_demo.gd), as the Hora Cero preview in Spanish, with a fresh player's
# user data and the game's own sound.
# usage: horacero_demo.sh <timeline|record> <plaza|riachuelo> <out dir> [width height]
#   record: Godot's movie writer (30 fps, the game's sound) to <out>/<part>.avi, turned at once into <out>/<part>.mkv
#   (H.264 CRF 14, 4:2:0, the sound as PCM) and the .avi deleted: the disk is small. The MJPEG of the .avi is written at
#   quality 0.92 (an override.cfg, with the window size): the HUD's small type stays clean.
#   timeline: no movie, the level played through without drawing; the log is the timeline.
# Env passed through: MOMENTS, PLAY_LIMIT, LAUNCH_S, BRIEF_S, REPORT_S, JUAN_CARRY (see horacero_demo.gd).
mode=$1; part=$2; out=$3; w=${4:-1920}; h=${5:-1080}
mkdir -p "$out"
GODOT=${GODOT:-/home/claude/tools47/Godot_v4.7.2-stable_linux.x86_64}
cd "$(dirname "$0")/../../godot"
exec 9>"${HORACERO_LOCK:-/tmp/horacero_godot.lock}"
flock 9
printf '[display]\n\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n\n[editor]\n\nmovie_writer/mjpeg_quality=0.92\n' $w $h > override.cfg
data=$(mktemp -d "${TMPDIR:-/tmp}/xdg-demo.XXXX")
movie=(--write-movie "$out/$part.avi")
[ "$mode" = "timeline" ] && movie=()
log="$out/${part}_${mode}.log"
SABOTEURS_PREVIEW=buenosaires SABOTEURS_LANG=${SABOTEURS_LANG:-es} SABOTEURS_TITLE=1 XDG_DATA_HOME=$data \
  xvfb-run -a -s "-screen 0 ${XVFB_SCREEN:-2200x2200}x24" $GODOT --path . --rendering-driver opengl3 "${movie[@]}" --fixed-fps 30 \
  --resolution ${w}x${h} --script res://../tools/trailer/horacero_demo.gd -- $mode $part "$out" 2>&1 \
  | grep --line-buffered -E "MARK|SPEED|DONE|ERROR|SCRIPT|^  t=|^END|briefing:|report:|salvo:" \
  | grep --line-buffered -v -E "ALSA|V-Sync|status < 0|resources still in use|ObjectDB|leaked|audio drivers|RID alloc|PagedAllocator" > "$log"
rm -f override.cfg
rm -rf "$data"
flock -u 9
if [ -f "$out/$part.avi" ]; then
  ffmpeg -v error -y -i "$out/$part.avi" -c:v libx264 -preset faster -crf 14 -pix_fmt yuv420p -c:a pcm_s16le "$out/$part.mkv" \
    && rm -f "$out/$part.avi"
fi
tail -5 "$log"
