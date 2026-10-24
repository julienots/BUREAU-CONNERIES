#!/bin/sh
# Rescans the project (class registry) then compile-checks every GDScript. Usage: tools/check.sh [maxlines]
cd "$(dirname "$0")/.." && timeout 600 godot --headless --path . --import >/dev/null 2>&1
timeout 180 godot --headless --path . res://tests/check_scripts.tscn 2>&1 | grep -vE "ALSA|audio_driver|init_output" | grep -A1 -E "SCRIPT ERROR|FAIL|checked" | grep -vE "^--$" | sed 's/^ *at: GDScript::reload/   at/' | awk '!seen[$0]++' | head -${1:-40}
