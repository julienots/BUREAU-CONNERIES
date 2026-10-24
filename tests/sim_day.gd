extends Node
## Headless simulation of a solo day with the player idle at their desk (or scripted).
## Logs AI states, events, notifications and sanity checks (nobody falls through the
## floor, nobody is stuck on furniture). Exit code 1 on failed checks.
## Run: godot --headless --path . res://tests/sim_day.tscn -- --secs=120 --scale=3

var secs := 120.0
var scale := 3.0
var game: Node
var s: Session
var _t := 0.0
var _log_t := 0.0
var fails: Array[String] = []
var events: Dictionary = {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.substr(7))
		elif a.begins_with("--scale="):
			scale = float(a.substr(8))
	Settings.values.tutorial_done = true
	Settings.values.day_minutes = 9.0
	Engine.time_scale = scale
	Engine.max_physics_steps_per_frame = 16
	Game.start_args = {"mode": "solo", "seed": 777}
	game = load("res://src/gameplay/game_scene.tscn").instantiate()
	add_child(game)
	s = game.session
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--debug="):
			s.brains[a.substr(8)].debug = true
	s.notified.connect(func(t, k): print("  [notif/%s] %s" % [k, t]))
	s.game_event_emitted.connect(func(type, d):
		events[type] = int(events.get(type, 0)) + 1
		if type in ["npc_reaction", "sanction", "testimony", "fall", "prank", "contradiction", "rumor_spread"]:
			print("  [event] ", type, " ", d))
	for c in s.characters.values():
		(c as Character).spoke.connect(func(txt): if randf() < 0.15: print("  [say] %s: %s" % [c.nick, txt]))

func _process(delta: float) -> void:
	_t += delta
	_log_t -= delta
	if _log_t <= 0.0:
		_log_t = 10.0
		var line := "t=%.0f %s fps=%d boss=%s |" % [_t, s.day.clock_text(), Engine.get_frames_per_second(), s.boss_brain.state]
		for id in s.brains:
			line += " %s:%s" % [id, s.brains[id].state]
		print(line)
		for c in s.characters.values():
			var ch := c as Character
			if ch.global_position.y < -1.0:
				fails.append("%s fell through the floor at %s" % [ch.id, ch.global_position])
			if ch.global_position.y > 0.6 and not ch.seated_on and not ch.is_down():
				print("  WARN %s elevated y=%.2f state=%s" % [ch.id, ch.global_position.y, s.brains[ch.id].state if s.brains.has(ch.id) else "-"])
	if _t > secs or s.day.is_over():
		print("events: ", events)
		print("suspicion: ", s.boss_brain.sus.scores)
		print("acts: ", s.acts.size(), " testimonies: ", s.testimonies.size())
		for f in fails:
			print("FAIL ", f)
		print("SIM DONE fails=%d" % fails.size())
		get_tree().quit(1 if fails.size() > 0 else 0)
