#!/bin/sh
# Starts a master server, runs tests/master_test.tscn against it (create/list/find/join), cleans up.
cd "$(dirname "$0")/.." || exit 1
godot --headless --path . -- --master --port=24800 > /tmp/om_master.log 2>&1 &
M=$!
sleep 5
timeout 60 godot --headless --path . res://tests/master_test.tscn 2>&1 | grep -E "created|rooms|found|unknown|joined|RESULT|SCRIPT"
RC=$?
grep "\[master\]" /tmp/om_master.log
for pid in $(grep -o "pid [0-9]*" /tmp/om_master.log | awk '{print $2}'); do kill "$pid" 2>/dev/null; done
kill $M 2>/dev/null
