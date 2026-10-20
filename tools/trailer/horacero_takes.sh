#!/bin/bash
# Renders the takes of horacero_takes.txt: the 16:9 ones into <wide dir>, the 9:16 ones into <upright dir>.
# usage: horacero_takes.sh <wide dir> <upright dir> [list]
wide=$1; up=$2; list=${3:-$(dirname "$0")/horacero_takes.txt}
here=$(cd "$(dirname "$0")" && pwd)
grep -v '^#' "$list" | while read -r w h shot rest; do
  [ -z "$shot" ] && continue
  dir=$wide; [ "$h" -gt "$w" ] && dir=$up
  env $rest "$here/horacero_run.sh" "$shot" "$w" "$h" "$dir" | grep MARK
done
