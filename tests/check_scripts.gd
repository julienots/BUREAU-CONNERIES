extends Node
## Compiles every script under res://src and res://tests; prints failures. Exit code = failures.

func _ready() -> void:
	var fails := 0
	var files: Array[String] = []
	_collect("res://src", files)
	_collect("res://tests", files)
	for f in files:
		var s: Script = load(f)
		if s == null or not s.can_instantiate() and not f.ends_with("check_scripts.gd"):
			if s == null or s.reload() != OK:
				print("FAIL ", f)
				fails += 1
	print("checked %d scripts, %d failures" % [files.size(), fails])
	get_tree().quit(fails)

func _collect(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		_collect(dir + "/" + sub, out)
