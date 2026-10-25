extends Node
## Captures the studio splash and the main menu as children of this test scene.
var out := "/tmp"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var boot: Node = load("res://src/ui/boot.tscn").instantiate()
	add_child(boot)
	await get_tree().create_timer(1.8).timeout
	get_viewport().get_texture().get_image().save_png(out + "/splash.png")
	boot.set_process_input(false)
	boot.set("_done", true)
	boot.queue_free()
	var menu: Node = load("res://src/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(3.0).timeout
	get_viewport().get_texture().get_image().save_png(out + "/menu.png")
	get_tree().quit()
