#!/bin/sh
# Menu-level Internet test: two game processes, one creates a game, the other finds it in
# the public list and joins with the code. RELAY=ws://127.0.0.1:18080/mqtt by default.
cd "$(dirname "$0")/.." || exit 1
RELAY=${RELAY:-ws://127.0.0.1:18080/mqtt}
CODE=${CODE:-U$(date +%s | tail -c 4)}
OUT=${OUT:-/tmp/om_relay_ui}
mkdir -p "$OUT"
godot --headless --path . res://tests/relay_ui_test.tscn -- --as=host --relay="$RELAY" --code="$CODE" > "$OUT/host.log" 2>&1 &
H=$!
sleep 6
godot --headless --path . res://tests/relay_ui_test.tscn -- --as=join --relay="$RELAY" --code="$CODE" > "$OUT/join.log" 2>&1
J=$?
wait $H
HS=$?
grep -h "ui-test\|SCRIPT ERROR" "$OUT/host.log" "$OUT/join.log"
echo "host exit=$HS join exit=$J"
[ $HS -eq 0 ] && [ $J -eq 0 ]
