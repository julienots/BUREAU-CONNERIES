extends Node
## Starts a solo day and captures screenshots at given times; optional scripted inputs.
## Run: xvfb-run godot --path . res://tests/play_shots.tscn -- --out=DIR --secs=30 --fast=1

var out := "/tmp/shots"
var secs := 30.0
var game: Node
var _t := 0.0
var _shots := [3.0, 9.0, 15.0, 25.0, 40.0, 60.0, 90.0]
var _i := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--secs="):
			secs = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(out)
	SaveGame.use_test_file()
	Settings.values.tutorial_done = true
	if "--low" in OS.get_cmdline_user_args():
		Settings.values.quality = "low"
	if "--touch" in OS.get_cmdline_user_args():
		Settings.values.touch_controls = "on"
	Settings.values.day_minutes = 6.0
	Game.start_args = {"mode": "solo", "seed": 4242}
	game = load("res://src/gameplay/game_scene.tscn").instantiate()
	add_child(game)

var _farce_done := false

func _process(delta: float) -> void:
	_t += delta
	if "--farce" in OS.get_cmdline_user_args() and not _farce_done and _t > 12.0:
		# honk at the nearest coworkers so reactions / prank bonus show up on screen
		_farce_done = true
		var s: Session = game.session
		var p: Character = s.player
		p.add_item("klaxon")
		var npc: Character = s.characters[s.npc_ids()[0]]
		p.global_position = s.world.nav_closest(npc.global_position + Vector3(1.5, 0, 1.5))
		var d := npc.global_position - p.global_position
		p.rotation.y = atan2(-d.x, -d.z)
		game.rig.yaw = p.rotation.y
		s.request_action(p, p.id, "use_klaxon", {"item": "klaxon"})
	if _i < _shots.size() and _t >= _shots[_i]:
		var s: Session = game.session
		print("t=%.1f clock=%s fps=%d boss=%s" % [_t, s.day.clock_text(), Engine.get_frames_per_second(), s.boss_brain.state if s.boss_brain else "-"])
		for id in s.brains:
			print("   ", id, " ", s.brains[id].state, " ", s.characters[id].global_position.snapped(Vector3(0.1,0.1,0.1)))
		get_viewport().get_texture().get_image().save_png("%s/play_%02d.png" % [out, _i])
		_i += 1
	if _t > secs:
		get_tree().quit()
