#!/bin/sh
# Real multiplayer test on one machine: 1 dedicated room server + 3 headless bot clients
# (1 director, 2 employees). Short day, then a rematch. Logs in $OUT.
# Usage: tools/mp_test.sh [seconds]
cd "$(dirname "$0")/.." || exit 1
SECS=${1:-150}
OUT=${OUT:-/tmp/om_mp}
PORT=${PORT:-24790}
mkdir -p "$OUT"
rm -f "$OUT"/*.log
godot --headless --path . -- --server --port=$PORT --code=TEST --name=Test --day=1.5 > "$OUT/server.log" 2>&1 &
SRV=$!
sleep 4
godot --headless --path . -- --bot --connect=127.0.0.1:$PORT --botrole=director --botname=Chef --botwait=3 --rematch=1 > "$OUT/bot_boss.log" 2>&1 &
B1=$!
sleep 1
godot --headless --path . -- --bot --connect=127.0.0.1:$PORT --botrole=employee --botname=Alice --rematch=1 > "$OUT/bot_alice.log" 2>&1 &
B2=$!
godot --headless --path . -- --bot --connect=127.0.0.1:$PORT --botrole=employee --botname=Bob --rematch=1 > "$OUT/bot_bob.log" 2>&1 &
B3=$!
sleep "$SECS"
kill $B1 $B2 $B3 $SRV 2>/dev/null
wait 2>/dev/null
echo "== server"; grep -E "^\[server\]|SCRIPT ERROR" "$OUT/server.log" | head -40
for b in boss alice bob; do echo "== bot $b"; grep -E "^\[bot|^\[client\]|SCRIPT ERROR" "$OUT/bot_$b.log" | head -40; done
