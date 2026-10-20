#!/bin/bash
# One take of the cinematic Hora Cero trailer (hc2_director.gd), as the Hora Cero preview in Spanish.
# usage: hc2_run.sh <take> <width> <height> <out.mkv> [view file]
#   The director pipes its frames into ffmpeg itself (<out.mkv>, H.264 CRF 12 4:4:4, 24 fps, no sound): nothing is
#   dumped on the disk. SUB (default 2) frames are drawn for each frame of the film (motion blur): Godot runs at a fixed
#   24 * SUB frames a second. "view" takes a view file (see shot_view) and writes stills next to it.
# The project overrides the window size (1280x720), which wins over --resolution: a temporary override.cfg sets the
# size. Env passed through: anything the director reads (SUB, TAKE_MAX, PROBE, PROBE_SETUP, CINE, ...).
take=$1; w=${2:-1920}; h=${3:-1080}; out=${4:-/tmp/hc2/$1.mkv}
mkdir -p "$(dirname "$out")"
GODOT=${GODOT:-/home/claude/tools47/Godot_v4.7.2-stable_linux.x86_64}
cd "$(dirname "$0")/../../godot"
# one Godot run at a time (they share override.cfg): a lock round the whole run
exec 9>"${HORACERO_LOCK:-/tmp/horacero_godot.lock}"
flock 9
printf '[display]\n\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' $w $h > override.cfg
fps=$((24 * ${SUB:-2}))
log="${out%.*}.log"
SABOTEURS_PREVIEW=buenosaires SABOTEURS_LANG=${SABOTEURS_LANG:-es} XDG_DATA_HOME=${XDG_DATA_HOME:-/tmp/claude-0/xdg-trailer} \
  xvfb-run -a -s "-screen 0 ${XVFB_SCREEN:-2200x2200}x24" $GODOT --path . --rendering-driver opengl3 --fixed-fps $fps \
  --resolution ${w}x${h} --script res://../tools/trailer/hc2_director.gd -- $take "$out" $5 2>&1 \
  | grep --line-buffered -E "DRAWCHECK|MARK|EVENT|DONE|ERROR|SCRIPT|probe|view|pipe|env:|^[a-z_0-9]+:|^  t=|^frame " \
  | grep --line-buffered -v -E "ALSA|V-Sync|status < 0|resources still in use|ObjectDB|leaked|audio drivers|RID alloc|PagedAllocator|never freed" > "$log"
rm -f override.cfg
flock -u 9
cat "$log"
