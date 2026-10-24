class_name ChoicePanel
extends Control
## Generic modal list picker. Options: [{label, value, sub?, disabled?, icon?}].

signal chosen(value: Variant)
signal closed

static var open_count := 0


static func open(parent: Control, title: String, desc: String, options: Array, cancel_text := "Annuler") -> ChoicePanel:
	var cp := ChoicePanel.new()
	cp.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(cp)
	cp._build(title, desc, options, cancel_text)
	return cp


func _build(title: String, desc: String, options: Array, cancel_text: String) -> void:
	open_count += 1
	theme = UiKit.theme()
	var p := UiKit.panel(Vector2(520, 0))
	UiKit.center_modal(self, p)
	var v := UiKit.vbox(8)
	p.add_child(v)
	v.add_child(UiKit.label(title, 28, UiKit.YELLOW, true))
	if desc != "":
		var d := UiKit.label(desc, 16, UiKit.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(480, 0)
		v.add_child(d)
	var list := UiKit.vbox(6)
	for o in options:
		var b := UiKit.button(String(o.label), func():
			chosen.emit(o.value)
			close(), 480, 19)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = o.get("disabled", false)
		if o.has("sub") and String(o.sub) != "":
			b.tooltip_text = String(o.sub)
			b.text += "\n   " + String(o.sub)
			b.custom_minimum_size.y = 70
		if o.has("icon"):
			b.icon = UiKit.icon(String(o.icon), 40).texture
			b.expand_icon = false
		list.add_child(b)
	v.add_child(UiKit.scroll(list, Vector2(500, mini(options.size() * 62, 430))))
	var cancel := UiKit.button(cancel_text, close, 200)
	v.add_child(cancel)
	if not options.is_empty():
		(list.get_child(0) as Control).call_deferred("grab_focus")


func close() -> void:
	if is_queued_for_deletion():
		return
	open_count = maxi(0, open_count - 1)
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
