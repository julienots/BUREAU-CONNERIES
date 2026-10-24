class_name WorkPanel
extends Control
## Short office tasks (5–10 s) that raise productivity: sort e-mails, stamp files,
## type a code. The result score is sent to the session which validates it
## (minimum duration, cap) — the UI cannot grant productivity by itself.

signal closed

var session: Session
var ch: Character
var target_pc := ""
var kind := ""
var box: VBoxContainer
var score := 0.0
var _items: Array = []
var _i := 0
var _ok := 0
var _t := 0.0
var _limit := 10.0
var _info: Label
var _timer_bar: ProgressBar
var _done := false

const MAILS := [["URGENT : réunion sur les réunions", true], ["Gagnez un iPhone !!!", false], ["Rapport Q3 — version finale v12", true],
	["Votre colis est bloqué (cliquez ici)", false], ["Planning des congés", true], ["Prince nigérian cherche associé", false],
	["Budget 2025 (relu)", true], ["Promo -90% sur les chaussettes", false], ["Note du directeur", true], ["Vous avez gagné un concours !", false]]
const WORDS := ["SYNERGIE", "KPI", "AGILE", "TABLEUR", "REPORTING", "BUDGET", "CAFE", "DOSSIER", "PLANNING", "REUNION"]


static func open(parent: Control, s: Session, c: Character, pc_id: String) -> WorkPanel:
	var wp := WorkPanel.new()
	wp.session = s
	wp.ch = c
	wp.target_pc = pc_id
	wp.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(wp)
	wp._build()
	return wp


func _build() -> void:
	ChoicePanel.open_count += 1
	theme = UiKit.theme()
	var p := UiKit.panel(Vector2(620, 380))
	UiKit.center_modal(self, p)
	box = UiKit.vbox(10)
	p.add_child(box)
	kind = ["mails", "stamps", "typing"][randi() % 3]
	_timer_bar = ProgressBar.new()
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size = Vector2(580, 10)
	match kind:
		"mails":
			box.add_child(UiKit.label("Trier la boîte mail", 28, UiKit.YELLOW, true))
			box.add_child(UiKit.label("Important ou spam ? (← / → ou boutons)", 16, UiKit.MUTED))
			_items = MAILS.duplicate()
			_items.shuffle()
			_items = _items.slice(0, 6)
			_limit = 12.0
		"stamps":
			box.add_child(UiKit.label("Tamponner les dossiers", 28, UiKit.YELLOW, true))
			box.add_child(UiKit.label("Tamponne quand le dossier passe dans la zone verte !", 16, UiKit.MUTED))
			_items = [0, 1, 2, 3, 4]
			_limit = 14.0
		"typing":
			box.add_child(UiKit.label("Saisie de données", 28, UiKit.YELLOW, true))
			box.add_child(UiKit.label("Tape le mot affiché puis Entrée.", 16, UiKit.MUTED))
			_items = WORDS.duplicate()
			_items.shuffle()
			_items = _items.slice(0, 4)
			_limit = 16.0
	box.add_child(_timer_bar)
	_info = UiKit.label("", 26)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.custom_minimum_size = Vector2(580, 90)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	var controls := UiKit.hbox(12)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(controls)
	match kind:
		"mails":
			controls.add_child(UiKit.button("← Spam", func(): _answer_mail(false), 220))
			controls.add_child(UiKit.button("Important →", func(): _answer_mail(true), 220))
		"stamps":
			var bar := Control.new()
			bar.custom_minimum_size = Vector2(560, 40)
			bar.name = "StampBar"
			box.add_child(bar)
			var zone := ColorRect.new()
			zone.color = Color(UiKit.GOOD, 0.45)
			zone.position = Vector2(240, 0)
			zone.size = Vector2(80, 40)
			bar.add_child(zone)
			var file := ColorRect.new()
			file.color = UiKit.YELLOW
			file.size = Vector2(26, 40)
			file.name = "File"
			bar.add_child(file)
			controls.add_child(UiKit.button("TAMPONNER ! (Espace)", _stamp, 320))
		"typing":
			var le := LineEdit.new()
			le.custom_minimum_size = Vector2(320, 50)
			le.name = "Input"
			le.text_submitted.connect(func(t): _typed(t))
			controls.add_child(le)
			le.call_deferred("grab_focus")
			controls.add_child(UiKit.button("OK", func(): _typed(le.text), 100))
	box.add_child(UiKit.button("Abandonner", func(): _finish(true), 220))
	_show()


func _show() -> void:
	if _i >= _items.size():
		_finish(false)
		return
	match kind:
		"mails":
			_info.text = "« %s »" % _items[_i][0]
		"stamps":
			_info.text = "Dossier %d / %d" % [_i + 1, _items.size()]
		"typing":
			_info.text = String(_items[_i])
			var le: LineEdit = find_child("Input", true, false)
			if le:
				le.text = ""


func _answer_mail(important: bool) -> void:
	if _done:
		return
	if bool(_items[_i][1]) == important:
		_ok += 1
		SoundFx.ui("mouse_click")
	else:
		SoundFx.ui("ui_error")
	_i += 1
	_show()


func _stamp() -> void:
	if _done or kind != "stamps":
		return
	var f: ColorRect = find_child("File", true, false)
	var x := f.position.x + 13
	SoundFx.ui("stamp")
	if x > 240 and x < 320:
		_ok += 1
	_i += 1
	f.position.x = -30
	_show()


func _typed(t: String) -> void:
	if _done or kind != "typing":
		return
	if t.strip_edges().to_upper() == String(_items[_i]):
		_ok += 1
		SoundFx.ui("ui_confirm", -6)
	else:
		SoundFx.ui("ui_error")
	_i += 1
	_show()


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_timer_bar.value = (1.0 - _t / _limit) * 100.0
	if kind == "stamps":
		var f: ColorRect = find_child("File", true, false)
		if f:
			f.position.x += delta * (260.0 + _i * 60.0)
			if f.position.x > 560:
				f.position.x = -30
				_i += 1
				_show()
	if _t > _limit:
		_finish(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left") and kind == "mails":
		_answer_mail(false)
	elif event.is_action_pressed("ui_right") and kind == "mails":
		_answer_mail(true)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE and kind == "stamps":
		_stamp()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		_finish(true)


func _finish(aborted: bool) -> void:
	if _done:
		return
	_done = true
	score = float(_ok) / maxf(1.0, _items.size())
	if not aborted:
		session.request_action(ch, target_pc, "work_done", {"score": score})
		session.notified.emit("Tâche terminée : %d/%d — productivité en hausse." % [_ok, _items.size()], "good")
	ch.humanoid.typing = false
	ChoicePanel.open_count = maxi(0, ChoicePanel.open_count - 1)
	closed.emit()
	queue_free()
