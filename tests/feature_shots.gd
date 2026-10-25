extends Node
## Screenshots of the new features in phone layout (touch HUD): meeting with the boss at the
## whiteboard, CEO visit, cartoon banana fall. Run with a display (xvfb):
## godot --path . --resolution 1560x720 res://tests/feature_shots.tscn -- --out=DIR

var out := "/tmp/shots"
var game: Node
var s: Session
var p: Character


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	SaveGame.use_test_file()
	Settings.values.tutorial_done = true
	Settings.values.touch_controls = "on"
	Settings.values.quality = "low"
	Game.start_args = {"mode": "solo", "seed": 77}
	game = load("res://src/gameplay/game_scene.tscn").instantiate()
	add_child(game)
	s = game.session
	p = s.player
	s.events.enabled = false
	s.pdg_at_min = -1.0
	_run()


func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)


func look(at: Vector3) -> void:
	var to := at - p.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	game.rig.yaw = p.rotation.y


func _run() -> void:
	await wait(3.0)
	game.hud.obj_panel.visible = false
	# --- meeting: everybody in, boss writing on the whiteboard
	s.day.start_meeting_now(40.0)
	await wait(0.5)
	var seats: Array = s.world.poi.meeting_seat
	var k := 1
	for id in s.brains:
		var c: Character = s.characters[id]
		if k >= seats.size():
			break
		c.global_position = seats[k].pos   # right next to a seat: they claim it and sit
		s.brains[id]._switch("meeting")
		k += 1
	var bp: Dictionary = s.world.poi.meeting_boss[0]
	s.director.global_position = bp.pos
	s.boss_brain._switch("meeting")
	s.boss_brain.step = 1
	var seat: Dictionary = seats[0]
	p.global_position = s.world.nav_closest(seat.pos)
	await wait(1.0)
	p.sit_on(s.world.ent(seat.chair_id))
	await wait(2.0)
	s.boss_brain._set_board(true)
	look(Vector3(1.0, 1.0, -11))
	await wait(1.5)
	s.request_action(p, p.id, "meet_grimace", {})
	await wait(0.8)
	await shot("meeting_board")
	s.boss_brain._set_board(false)
	await wait(1.5)
	await shot("meeting_watched")
	# --- end the meeting, CEO visit
	s.day._schedule.clear()
	await wait(1.0)
	p.stand_up()
	s.events.start("pdg_visit", s.now(), {})
	await wait(0.5)
	s.pdg_brain.set_physics_process(false)
	s.pdg.global_position = s.world.nav_closest(Vector3(-3.0, 0, 4.9))
	s.pdg.stop()
	s.director.global_position = s.world.nav_closest(Vector3(-1.8, 0, 5.9))
	p.global_position = s.world.nav_closest(Vector3(-7.2, 0, 4.9))
	look(s.pdg.global_position)
	await wait(0.4)
	s.npc_say(s.pdg, s.barks.pick("pdg_comment"), "neutral")
	await wait(1.5)
	await shot("pdg_visit")
	# --- banana: the CEO flies
	s.pdg.velocity = Vector3(0, 0, 2.5)
	s.pdg.slip("banana", "player")
	await wait(0.35)
	await shot("banana_flip")
	await wait(1.4)
	await shot("banana_stars")
	get_tree().quit()
