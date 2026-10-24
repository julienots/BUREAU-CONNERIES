extends Node
## Audio playback: UI sounds, music, ambience loops, positional SFX with wall occlusion
## (low-pass + attenuation), and the gibberish character voices.

const SFX_DIR := "res://assets/audio/sfx/"
const VOICE_DIR := "res://assets/audio/voices/"
const MUSIC_DIR := "res://assets/audio/music/"
const MAX_3D := 28

var _cache: Dictionary = {}
var _music: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _ambience: Array[AudioStreamPlayer] = []
var _ui: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_idx := 0
## Callable(from: Vector3, to: Vector3) -> int  : number of walls between two points (set by the session)
var occlusion_counter: Callable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "Sfx", "Voices", "Ambience"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_music = _make_player("Music")
	_music_b = _make_player("Music")
	_ui = _make_player("Sfx")
	for i in 2:
		_ambience.append(_make_player("Ambience"))
	for i in MAX_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "Sfx"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 4.0
		p.max_distance = 45.0
		p.panning_strength = 0.8
		add_child(p)
		_pool.append(p)
	Settings.apply_audio()


func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_cache[path] = s
	return s


func sfx_stream(name: String) -> AudioStream:
	return stream(SFX_DIR + name + ".wav")


## Variation helper: "step_carpet" -> random among step_carpet_0..3 if they exist.
func pick_variant(base: String, count: int) -> String:
	return "%s_%d" % [base, randi() % count]


func ui(name: String, volume_db := 0.0) -> void:
	var s := sfx_stream(name)
	if s == null:
		return
	_ui.stream = s
	_ui.volume_db = volume_db
	_ui.play()


func ui_overlap(name: String, volume_db := 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.bus = "Sfx"
	p.stream = sfx_stream(name)
	p.volume_db = volume_db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## Positional one-shot. `loudness` 0..100 maps to volume; walls between the listener and
## the source muffle the sound so the player can tell the director is behind a wall.
func play_at(name: String, pos: Vector3, loudness := 50.0, pitch := 1.0, bus := "Sfx", folder := SFX_DIR) -> AudioStreamPlayer3D:
	var s := stream(folder + name + ".wav")
	if s == null:
		return null
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % MAX_3D
	p.stop()
	if p.get_parent() != self:
		p.get_parent().remove_child(p)
		add_child(p)
	p.stream = s
	p.bus = bus
	p.global_position = pos
	p.pitch_scale = pitch
	p.volume_db = lerpf(-22.0, 4.0, clampf(loudness / 100.0, 0.0, 1.0))
	p.attenuation_filter_cutoff_hz = 20500.0
	var walls := _walls_to_listener(pos)
	if walls > 0:
		p.attenuation_filter_cutoff_hz = maxf(600.0, 4500.0 / float(walls))
		p.volume_db -= 5.0 * walls
	p.play()
	return p


func _walls_to_listener(pos: Vector3) -> int:
	if not occlusion_counter.is_valid():
		return 0
	var vp := get_viewport()
	if vp == null:
		return 0
	var cam := vp.get_camera_3d()
	if cam == null:
		return 0
	return int(occlusion_counter.call(cam.global_position, pos))


## Gibberish voice. emotion in: neutral happy laugh angry panic surprised suspicious embarrassed
func voice(voice_id: String, emotion: String, pos: Vector3, pitch := 1.0, loud := 55.0) -> void:
	var take := randi() % 3
	var name := "%s_%s_%d" % [voice_id, emotion, take]
	if not ResourceLoader.exists(VOICE_DIR + name + ".wav"):
		name = "%s_neutral_%d" % [voice_id, take]
	play_at(name, pos, loud, pitch * randf_range(0.95, 1.06), "Voices", VOICE_DIR)


func music(name: String, fade := 1.0) -> void:
	var s := stream(MUSIC_DIR + name + ".wav")
	if s == null:
		return
	if _music.stream == s and _music.playing:
		return
	if s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)
	var old := _music
	_music = _music_b
	_music_b = old
	_music.stream = s
	_music.volume_db = -40.0
	_music.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_music, "volume_db", 0.0, fade)
	tw.tween_property(_music_b, "volume_db", -40.0, fade)
	tw.chain().tween_callback(_music_b.stop)


func stop_music(fade := 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", -40.0, fade)
	tw.tween_callback(_music.stop)


func ambience(names: Array) -> void:
	for i in _ambience.size():
		var p := _ambience[i]
		if i < names.size():
			var s := sfx_stream(names[i])
			if s is AudioStreamWAV:
				(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
				(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)
			if p.stream != s:
				p.stream = s
				p.play()
		else:
			p.stop()


## Looping positional emitter owned by a world object (printer, radio, microwave...).
func make_loop_emitter(parent: Node3D, name: String, folder := SFX_DIR, bus := "Sfx") -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	var s := stream(folder + name + ".wav")
	if s is AudioStreamWAV:
		s = (s as AudioStreamWAV).duplicate()
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)
	p.stream = s
	p.bus = bus
	p.unit_size = 4.0
	p.max_distance = 40.0
	parent.add_child(p)
	return p
