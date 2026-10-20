#!/bin/bash
# Hora Cero trailer takes (horacero_director.gd), one per run, in Spanish (needs xvfb-run and ffmpeg).
# usage: horacero_run.sh <shot> <width> <height> <outdir> [probe file]
#   A take is recorded by Godot's movie writer to <outdir>/<shot>.avi, then turned at once into a near-lossless
#   intermediate (<shot>.mkv: H.264 CRF 10, 4:4:4, the game's sound as PCM) and the .avi deleted: the disk is small.
#   "probe" takes a probe file (see the director) and writes stills next to it instead.
# The project overrides the window size (1280x720), which wins over --resolution: a temporary override.cfg sets the
# size the movie is recorded at. Env passed through: anything the director reads (PLAY_AT, TAKE_MAX, PROBE_SETUP ...).
shot=$1; w=${2:-1920}; h=${3:-1080}; out=${4:-/tmp/horacero/takes}
mkdir -p "$out"
GODOT=${GODOT:-godot}
cd "$(dirname "$0")/../../godot"
# one Godot run at a time (they share override.cfg, and llvmpipe has the CPUs to itself): a lock around the whole run
exec 9>"${HORACERO_LOCK:-/tmp/horacero_godot.lock}"
flock 9
printf '[display]\n\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' $w $h > override.cfg
data=$(mktemp -d "${TMPDIR:-/tmp}/xdg-tr-take.XXXX")
movie=(--write-movie "$out/$shot.avi")
[ "$shot" = "probe" ] && movie=()
HORACERO_LANG=${HORACERO_LANG:-es} XDG_DATA_HOME=$data \
  xvfb-run -a -s "-screen 0 ${XVFB_SCREEN:-2200x2200}x24" $GODOT --path . --rendering-driver opengl3 "${movie[@]}" --fixed-fps 30 \
  --resolution ${w}x${h} --script res://../tools/trailer/horacero_director.gd -- $shot $5 2>&1 \
  | grep -E "MARK|SHOT|DONE|ERROR|SCRIPT|WARNING|probe|^[a-z_]+:|^  t=" \
  | grep -v -E "ALSA|V-Sync|status < 0|resources still in use|ObjectDB|leaked|audio drivers|RID alloc|PagedAllocator" > "$out/$shot.log"
rm -f override.cfg
rm -rf "$data"
flock -u 9
if [ -f "$out/$shot.avi" ]; then
  ffmpeg -v error -y -i "$out/$shot.avi" -c:v libx264 -preset faster -crf 10 -pix_fmt yuv444p -c:a pcm_s16le "$out/$shot.mkv" \
    && rm -f "$out/$shot.avi"
fi
cat "$out/$shot.log"
