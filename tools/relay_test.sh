#!/bin/sh
# Internet-relay multiplayer test on one machine: a room server + 3 headless bot players
# (1 director, 2 employees), all talking ONLY through an MQTT broker over WebSocket.
# Needs a broker with a WebSocket listener, e.g. a local one: RELAY=ws://127.0.0.1:18080/mqtt
# Usage: RELAY=ws://host:port/mqtt tools/relay_test.sh [seconds]
cd "$(dirname "$0")/.." || exit 1
SECS=${1:-150}
OUT=${OUT:-/tmp/om_relay}
RELAY=${RELAY:-ws://127.0.0.1:18080/mqtt}
CODE=${CODE:-T$(date +%s | tail -c 4)}
mkdir -p "$OUT"
rm -f "$OUT"/*.log
godot --headless --path . -- --server --relay="$RELAY" --code="$CODE" --name=RelayTest --day=1.5 > "$OUT/server.log" 2>&1 &
SRV=$!
sleep 5
godot --headless --path . -- --bot --relay="$RELAY" --code="$CODE" --botrole=director --botname=Chef --botwait=3 --rematch=1 > "$OUT/bot_boss.log" 2>&1 &
B1=$!
sleep 1
godot --headless --path . -- --bot --relay="$RELAY" --code="$CODE" --botrole=employee --botname=Alice --rematch=1 > "$OUT/bot_alice.log" 2>&1 &
B2=$!
godot --headless --path . -- --bot --relay="$RELAY" --code="$CODE" --botrole=employee --botname=Bob --rematch=1 > "$OUT/bot_bob.log" 2>&1 &
B3=$!
sleep "$SECS"
kill $B1 $B2 $B3 $SRV 2>/dev/null
wait 2>/dev/null
echo "== server"; grep -E "^\[server\]|SCRIPT ERROR" "$OUT/server.log" | head -40
for b in boss alice bob; do echo "== bot $b"; grep -E "^\[bot|^\[client\]|SCRIPT ERROR" "$OUT/bot_$b.log" | head -40; done
