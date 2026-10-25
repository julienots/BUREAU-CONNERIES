extends Node3D
## Renders the cast side by side with emotes (visual check / promo image).
var out := "/tmp/lineup.png"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var w := OfficeWorld.new()
	add_child(w)
	OfficeBuilder.build(w, 5, "high", false)
	var cast: Array = [Data.director] + Data.coworkers + [Data.player_default]
	var emotes := ["angry", "suspicious", "laugh", "", "surprised", "panic", "shrug", "embarrassed", "point", "wave"]
	for i in cast.size():
		var h := Humanoid.new()
		add_child(h)
		h.build(cast[i].look)
		h.position = Vector3(-17.0 + i * 0.85, 0, 5.0)
		h.rotation_degrees.y = 180 + (i - 4) * 4
		h.emote = emotes[i % emotes.size()]
		h.posture = 0.8 if i == 0 else 0.0
		var l := Label3D.new()
		l.text = cast[i].get("name", "")
		l.position = Vector3(0, 2.05, 0)
		l.font_size = 40
		l.outline_size = 10
		l.pixel_size = 0.003
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		h.add_child(l)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50
	cam.position = Vector3(-13.2, 1.45, 10.3)
	cam.look_at(Vector3(-13.2, 1.0, 5.0))
	await get_tree().create_timer(2.0).timeout
	get_viewport().get_texture().get_image().save_png(out)
	cam.fov = 30
	cam.position = Vector3(-14.4, 1.62, 7.4)
	cam.look_at(Vector3(-14.4, 1.45, 5.0))
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(out.replace(".png", "_close.png"))
	get_tree().quit()
