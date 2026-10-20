#!/usr/bin/env bash
# Imports the project, then runs every test suite headless, one after another; exits non-zero if any fails.
#   GODOT=/path/to/Godot_v4.7-stable tools/run_tests.sh              # all suites
#   GODOT=/path/to/Godot_v4.7-stable tools/run_tests.sh plaza_rules  # only the ones named
# GODOT names the Godot 4.7 binary (else `godot` on the PATH). Each suite prints its checks and FAIL lines; its log is
# kept in $LOGS (default: a temporary folder, removed when everything passes) when it fails.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || command -v godot4 || true)}"
if [ -z "$GODOT" ]; then
	echo "set GODOT to the Godot 4.7 binary" >&2
	exit 2
fi
if [ -n "${LOGS:-}" ]; then
	mkdir -p "$LOGS"
	OWN_LOGS=0
else
	LOGS="$(mktemp -d)"
	OWN_LOGS=1
fi
SUITES=(plaza_rules plaza_playthrough plaza_scene riachuelo_rules riachuelo_playthrough riachuelo_scene world_visuals
	hud_actions icons art_pack voice_lines audio_events lang_es launch_screen)
if [ $# -gt 0 ]; then
	SUITES=("$@")
fi

echo "importing..."
"$GODOT" --headless --path "$ROOT/godot" --import > "$LOGS/import.log" 2>&1 || {
	echo "import failed: $LOGS/import.log" >&2
	exit 1
}

failed=()
for suite in "${SUITES[@]}"; do
	log="$LOGS/$suite.log"
	start=$(date +%s)
	"$GODOT" --headless --path "$ROOT/godot" --script "res://tests/$suite.gd" > "$log" 2>&1
	code=$?
	fails=$(grep -c -E "FAIL \[|FAIL:|SCRIPT ERROR" "$log")
	summary=$(grep -E "_CHECKS=|[0-9]+ checks, [0-9]+ failures" "$log" | tail -1)
	echo "$suite: exit $code, $(( $(date +%s) - start ))s, $summary"
	if [ $code -ne 0 ] || [ "$fails" -ne 0 ]; then
		failed+=("$suite")
		grep -E "FAIL \[|FAIL:|SCRIPT ERROR" "$log" | head -20
	else
		rm -f "$log"
	fi
done

if [ ${#failed[@]} -gt 0 ]; then
	echo "FAILED: ${failed[*]} (logs in $LOGS)"
	exit 1
fi
if [ $OWN_LOGS -eq 1 ]; then
	rm -rf "$LOGS"
fi
echo "all ${#SUITES[@]} suites passed"
