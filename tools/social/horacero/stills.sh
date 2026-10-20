#!/bin/bash
# Hora Cero launch stills: every picture make_social.py lays its type on, rendered from the real game by
# tools/trailer/horacero_director.gd's "probe" shot, each at its format's own size, into <out dir>.
# usage: stills.sh <out dir> [run ...]          (runs: the names below; none = all of them)
# One Godot run at a time. Each run gets an empty HOME (no real settings, no saved progress) and, where sandbox-exec
# exists (a Mac), no network (the finale would post to the live leaderboard). Godot opens its own window: on a Mac
# that is all it needs; on Linux without a display the run goes through xvfb-run. A window the screen cannot hold
# (the 4K key art on a laptop) is drawn through PROBE_CANVAS: the picture at full size, the window scaled down.
out=${1:?usage: stills.sh <out dir> [run ...]}; shift
mkdir -p "$out/probes"
out=$(cd "$out" && pwd)
GODOT=${GODOT:-"/Applications/Godot 4.7.2.app/Contents/MacOS/Godot"}
here=$(cd "$(dirname "$0")" && pwd)
project=$(cd "$here/../../../godot" && pwd)
wanted=" $* "

# Juan Salvo takes aim at a cascarudo before the Casa Rosada's lit arch (the rules stopped before the shot)
AIM="PROBE_SETUP=aim PROBE_SHOOT=c1 AIM_JUAN=200,100 AIM_BEAST=212,97.5 AIM_FACE=168"

# run <name> <w> <h> "<env>" <probe line> ...: one Godot run, its stills named by the lines. A "_" line is a framing
# tried and dropped, kept because every line moves the night on 6 frames: the still after it stays the one approved.
run() {
  local name=$1 w=$2 h=$3 env=$4; shift 4
  [ "$wanted" != "  " ] && [[ "$wanted" != *" $name "* ]] && return
  local file="$out/probes/$name.txt"
  printf '%s\n' "$@" > "$file"
  local home; home=$(mktemp -d "${TMPDIR:-/tmp}/hc-stills-home.XXXXXX")
  local canvas=() size=("$w" "$h")
  if [ "$w" -gt 2400 ]; then canvas=("PROBE_CANVAS=${w}x${h}"); size=($((w / 2)) $((h / 2))); fi
  printf '[display]\n\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "${size[@]}" \
    > "$project/override.cfg"
  local wrap=()
  command -v sandbox-exec > /dev/null && wrap=(sandbox-exec -p '(version 1)(allow default)(deny network*)')
  [ -z "$DISPLAY" ] && [ "$(uname)" != Darwin ] && wrap=(xvfb-run -a -s "-screen 0 2200x2200x24")
  (cd "$project" && env HOME="$home" SABOTEURS_PREVIEW=buenosaires SABOTEURS_LANG=es $env "${canvas[@]}" \
    "${wrap[@]}" "$GODOT" --path . --rendering-driver opengl3 --fixed-fps 30 --resolution "${size[0]}x${size[1]}" \
    --script res://../tools/trailer/horacero_director.gd -- probe "$file" > "$out/probes/$name.log" 2>&1)
  rm -f "$project/override.cfg"
  rm -rf "$home"
  # the director saves the stills beside the probe file
  rm -f "$out/probes"/_*.png
  mv "$out/probes"/*.png "$out/" 2> /dev/null
  echo "$name: $(grep -E '^probe [a-z]' "$out/probes/$name.log" | grep -v ' _' | tr '\n' ' ')"
}

# Instagram carousel, 1080x1350
run cover 1080 1350 "" \
  "ig1 L 199.97 84.00 6.0 270.0 -7.0 12.31 58.0"
# (the carry in the game's own view: a lens close to it shows the carried body as the flat thing it is)
run carry 1080 1350 "PROBE_SETUP=carry SOME_IN=16" \
  "ig2 @salvo 4.0 -0.3 16 25 52 hud quiet"
run rush 1080 1350 "PROBE_SETUP=rush RUSH_X=166 RUSH_Z=86" \
  "_a L 159 85 15 265 6 1.4 50" \
  "ig3 L 159 85 15 268 5 1.6 48"
run subte 1080 1350 "PROBE_SETUP=rescue" \
  "_a @benteveo 0 0 14 -45 52 hud quiet" \
  "ig4 @benteveo 0 0 12 -60 52 hud quiet"
run comic 1080 1350 "PROBE_SETUP=play PLAY_AT=40 PROBE_SELECT=lechuza" \
  "_a @benteveo 0 0 15 -45 52 hud quiet ink" \
  "ig5 @lechuza 0 0 15 -45 52 hud quiet ink"
run riachuelo 1080 1350 "PROBE_LEVEL=riachuelo PROBE_SETUP=ria_crossing" \
  "_a L 150 120 90 230 6 20 44" \
  "_b L 145 118 100 245 8 22 40" \
  "ig6 L 150 122 80 215 5 18 46"
run square_end 1080 1350 "PROBE_SETUP=buried" \
  "_a L 244 82 70 270 6 12 58" \
  "_b L 200 84 90 270 10 14 50" \
  "ig7 L 160 84 110 270 14 10 46"

# Instagram stories, 1080x1920
run story_snow 1080 1920 "PROBE_SETUP=play PLAY_AT=13.4" \
  "story1 @benteveo 1 3 16 -45 52 hud quiet"
run story_aim 1080 1920 "$AIM" \
  "story2 L 201.34 100.22 6.0 299.4 -15.8 2.83 77.8"

# X and link previews, 1600x900
run x_call 1600 900 "PROBE_SETUP=play PLAY_AT=14" \
  "x1 @benteveo 2 2 20 -45 52 hud quiet"
run x_rush 1600 900 "PROBE_SETUP=rush SOME_IN=14 RUSH_X=166 RUSH_Z=88" \
  "x2 160 88 22 -30 50 hud quiet"
run x_aim 1600 900 "$AIM" \
  "x3 L 201.32 98.34 6 313 0 1.33 44"

# the Instagram post (1080x1080), the LinkedIn / link card (1200x627), the key art (3840x2160, no HUD)
run square 1080 1080 "$AIM" \
  "square L 201.60 99.89 6.0 298.6 -10.9 2.35 75.0"
run linkedin 1200 627 "$AIM" \
  "linkedin L 201.02 98.04 6 317 0 1.33 44"
run keyart 3840 2160 "$AIM" \
  "keyart L 203 98.5 6 303 3 1.5 40"
