extends Node
## Global game flow: scene switching, current session reference, game clock helpers.

signal session_changed

var session: Node = null          # current Session (authority or client replica)
var start_args: Dictionary = {}   # parameters for the next game scene (mode, role...)
var _now := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _physics_process(delta: float) -> void:
	_now += delta


## Game time in seconds (scaled by Engine.time_scale, frozen while paused).
## All gameplay timestamps use this clock.
func time() -> float:
	return _now


func set_session(s: Node) -> void:
	session = s
	SoundFx.occlusion_counter = Callable()
	if s and s.get("world"):
		SoundFx.occlusion_counter = s.world.count_walls
	session_changed.emit()


func goto_scene(path: String, args := {}) -> void:
	start_args = args
	get_tree().paused = false
	get_tree().call_deferred("change_scene_to_file", path)


func goto_menu() -> void:
	if Net.is_active():
		Net.leave()
	goto_scene("res://src/ui/main_menu.tscn")


func start_solo() -> void:
	goto_scene("res://src/gameplay/game_scene.tscn", {"mode": "solo"})
