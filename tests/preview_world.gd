extends Node3D
## Debug: builds the office and saves screenshots from several viewpoints.
## Run: xvfb-run godot --path . res://tests/preview_world.tscn -- --out=/tmp/shots

var shots := [
	["overview", Vector3(0, 26, 22), Vector3(0, 0, -1)],
	["open_space", Vector3(-20, 2.2, 10.5), Vector3(-8, 0.8, 2)],
	["desks_close", Vector3(-13.5, 1.7, 4.8), Vector3(-16, 0.8, 1.6)],
	["meeting", Vector3(11, 2.0, -9), Vector3(2, 0.8, -11.5)],
	["break", Vector3(13, 1.9, -9), Vector3(18, 0.9, -13)],
	["boss", Vector3(15, 2.0, 11), Vector3(20, 0.8, 6)],
	["archives", Vector3(-13, 2.0, -8.6), Vector3(-17, 0.8, -12)],
	["corridor", Vector3(-20, 1.7, -6.5), Vector3(10, 1.2, -6.5)],
]
var out := "/tmp/shots"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var w := OfficeWorld.new()
	add_child(w)
	var t0 := Time.get_ticks_msec()
	OfficeBuilder.build(w, 1234, "high")
	print("build ms: ", Time.get_ticks_msec() - t0, " interactables: ", w.interactables.size(), " props: ", w.props.size(), " desks: ", w.desks.size())
	var nm: NavigationMesh = w.nav_region.navigation_mesh
	print("nav polys: ", nm.get_polygon_count())
	var cam := Camera3D.new()
	cam.fov = 70
	add_child(cam)
	await get_tree().create_timer(1.5).timeout
	for s in shots:
		cam.global_position = s[1]
		cam.look_at(s[2] if s[0] != "overview" else Vector3(0, 0, -1), Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.3).timeout
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, s[0]])
	get_tree().quit()
