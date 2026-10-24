class_name InterrogationPanel
extends Control
## The director confronts the player: deny, give an excuse, accuse someone, or confess.
## The outcome is decided by the session from the real evidence, not by this UI.

signal closed

var session: Session
var ch: Character
var info: Dictionary
var _answered := false
var _t := 20.0
var _bar: ProgressBar


static func open(parent: Control, s: Session, c: Character, i: Dictionary) -> InterrogationPanel:
	var ip := InterrogationPanel.new()
	ip.session = s
	ip.ch = c
	ip.info = i
	ip.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(ip)
	ip._build()
	return ip


func _build() -> void:
	ChoicePanel.open_count += 1
	theme = UiKit.theme()
	var p := UiKit.panel(Vector2(640, 0))
	p.add_theme_stylebox_override("panel", UiKit.box(UiKit.DARK, 18, 3, UiKit.BAD))
	UiKit.center_modal(self, p)
	var v := UiKit.vbox(10)
	p.add_child(v)
	v.add_child(UiKit.label("%s t'interpelle !" % info.get("boss", "Le directeur"), 32, UiKit.BAD, true))
	var d := UiKit.label(String(info.get("act_text", "")), 19)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(600, 0)
	v.add_child(d)
	v.add_child(UiKit.label(String(info.get("hint", "")), 16, UiKit.WARN))
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(600, 8)
	v.add_child(_bar)
	v.add_child(UiKit.button("Nier : « Ce n'était pas moi ! »", func(): _answer("deny", {}), 600))
	v.add_child(UiKit.button("Trouver une excuse", func(): _answer("excuse", {}), 600))
	v.add_child(UiKit.button("Accuser quelqu'un d'autre…", _accuse, 600))
	v.add_child(UiKit.button("Avouer (sanction réduite)", func(): _answer("confess", {}), 600))


func _accuse() -> void:
	var opts: Array = []
	for c in info.get("candidates", []):
		opts.append({"label": String(c.name), "value": String(c.id)})
	var cp := ChoicePanel.open(self, "Accuser…", "Si le directeur l'a vu ailleurs au même moment, ça se retournera contre toi.", opts)
	cp.chosen.connect(func(v): _answer("accuse", {"accused": v}))


func _answer(choice: String, params: Dictionary) -> void:
	if _answered:
		return
	_answered = true
	session.request_action(ch, "boss", "answer_" + choice, params)
	close()


func _process(delta: float) -> void:
	_t -= delta
	if _bar:
		_bar.value = _t / 20.0 * 100.0
	if _t <= 0.0 and not _answered:
		_answer("deny", {})


func close() -> void:
	if is_queued_for_deletion():
		return
	ChoicePanel.open_count = maxi(0, ChoicePanel.open_count - 1)
	closed.emit()
	queue_free()
