extends Node
## Player settings (graphics, audio, controls, accessibility, gameplay difficulty).
## Persisted to user://settings.cfg. Also owns the input map so keys can be remapped.

signal changed

const PATH := "user://settings.cfg"

var values := {
	"quality": "auto",          # low / medium / high / auto
	"render_scale": 1.0,
	"shadows": true,
	"ssao": true,
	"glow": true,
	"npc_count": 8,
	"vol_master": 0.9,
	"vol_music": 0.45,
	"vol_sfx": 0.9,
	"vol_voices": 0.85,
	"vol_ambience": 0.6,
	"mouse_sens": 0.25,
	"touch_sens": 0.35,
	"invert_y": false,
	"reduce_effects": false,
	"subtitles_size": 1.0,
	"day_minutes": 9.0,
	"boss_memory": 1.0,          # multiplier on the director memory capacity
	"difficulty": 1.0,
	"llm_enabled": false,
	"llm_endpoint": "http://127.0.0.1:11434/api/generate",
	"llm_model": "qwen2.5:0.5b",
	"server_address": "127.0.0.1",
	"server_port": 24680,
	"player_name": "Joueur",
	"tutorial_done": false,
	"touch_controls": "auto",    # auto / on / off
}

# action -> [physical keycodes] ; mouse buttons are encoded as negative numbers
const DEFAULT_KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	"crouch": [KEY_CTRL, KEY_C],
	"jump": [KEY_SPACE],
	"interact": [KEY_E, -MOUSE_BUTTON_LEFT],
	"alt_action": [KEY_F],
	"next_action": [KEY_TAB],
	"drop": [KEY_G],
	"throw": [-MOUSE_BUTTON_RIGHT],
	"inventory": [KEY_I],
	"objectives": [KEY_O],
	"use_item": [KEY_R],
	"pause": [KEY_ESCAPE, KEY_P],
	"notebook": [KEY_N],
	"slot_1": [KEY_1], "slot_2": [KEY_2], "slot_3": [KEY_3], "slot_4": [KEY_4],
}
var keys: Dictionary = {}


func _ready() -> void:
	keys = DEFAULT_KEYS.duplicate(true)
	load_settings()
	apply_input_map()
	apply_audio()


func get_v(key: String) -> Variant:
	return values.get(key)


func set_v(key: String, v: Variant, save := true) -> void:
	values[key] = v
	if key.begins_with("vol_"):
		apply_audio()
	if save:
		save_settings()
	changed.emit()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in values.keys():
		if cfg.has_section_key("settings", k):
			var v: Variant = cfg.get_value("settings", k)
			if typeof(v) == typeof(values[k]) or (typeof(values[k]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
				values[k] = v
	for a in DEFAULT_KEYS.keys():
		if cfg.has_section_key("keys", a):
			var arr: Variant = cfg.get_value("keys", a)
			if typeof(arr) == TYPE_ARRAY:
				keys[a] = arr


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in values.keys():
		cfg.set_value("settings", k, values[k])
	for a in keys.keys():
		cfg.set_value("keys", a, keys[a])
	cfg.save(PATH)


func apply_input_map() -> void:
	for action in keys.keys():
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.2)
		for code in keys[action]:
			if int(code) < 0:
				var mb := InputEventMouseButton.new()
				mb.button_index = -int(code) as MouseButton
				InputMap.action_add_event(action, mb)
			else:
				var ev := InputEventKey.new()
				ev.physical_keycode = int(code) as Key
				InputMap.action_add_event(action, ev)
	# gamepad support (basic)
	_add_joy("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_btn("interact", JOY_BUTTON_A)
	_add_joy_btn("alt_action", JOY_BUTTON_X)
	_add_joy_btn("drop", JOY_BUTTON_B)
	_add_joy_btn("crouch", JOY_BUTTON_RIGHT_STICK)
	_add_joy_btn("run", JOY_BUTTON_LEFT_STICK)
	_add_joy_btn("pause", JOY_BUTTON_START)


func _add_joy(action: String, axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _add_joy_btn(action: String, b: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = b
	InputMap.action_add_event(action, ev)


func rebind(action: String, physical_keycode: int) -> void:
	keys[action] = [physical_keycode]
	apply_input_map()
	save_settings()


func reset_keys() -> void:
	keys = DEFAULT_KEYS.duplicate(true)
	apply_input_map()
	save_settings()


func key_label(action: String) -> String:
	var arr: Array = keys.get(action, [])
	if arr.is_empty():
		return "?"
	var code := int(arr[0])
	if code < 0:
		return {MOUSE_BUTTON_LEFT: "Clic G", MOUSE_BUTTON_RIGHT: "Clic D", MOUSE_BUTTON_MIDDLE: "Clic M"}.get(-code, "Souris")
	# map the physical key to the user's layout (AZERTY shows Z/Q instead of W/A) when supported
	if DisplayServer.get_name() in ["Windows", "macOS", "X11", "Wayland"]:
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code as Key))
	return OS.get_keycode_string(code as Key)


func apply_audio() -> void:
	for bus in ["Master", "Music", "Sfx", "Voices", "Ambience"]:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var key: String = "vol_master" if bus == "Master" else "vol_" + bus.to_lower()
		var v: float = values.get(key, 1.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)


func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


func use_touch() -> bool:
	match String(values.touch_controls):
		"on":
			return true
		"off":
			return false
	return is_mobile() or DisplayServer.is_touchscreen_available() and OS.has_feature("web")


func effective_quality() -> String:
	if values.quality != "auto":
		return values.quality
	return "low" if is_mobile() else "high"
