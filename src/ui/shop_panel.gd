class_name ShopPanel
extends Control
## "SuperAmazone" gadget shop (opened from the player's own PC). Shows name, icon,
## description, price, effect and unlock condition. Purchases are validated by the
## session/economy (money, tier, uniqueness); the UI only sends the request.

signal closed

var session: Session
var ch: Character
var grid: GridContainer
var money_l: Label
var stock_box: VBoxContainer


static func open(parent: Control, s: Session, c: Character) -> ShopPanel:
	var sp := ShopPanel.new()
	sp.session = s
	sp.ch = c
	sp.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(sp)
	sp._build()
	return sp


func _build() -> void:
	ChoicePanel.open_count += 1
	theme = UiKit.theme()
	var p := UiKit.panel(Vector2(980, 600))
	UiKit.center_modal(self, p)
	var v := UiKit.vbox(10)
	p.add_child(v)
	var head := UiKit.hbox(10)
	v.add_child(head)
	head.add_child(UiKit.label("SuperAmazone", 34, UiKit.YELLOW, true))
	head.add_child(UiKit.label("Livraison immédiate au bureau", 16, UiKit.MUTED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	money_l = UiKit.label("", 26, UiKit.YELLOW, true)
	head.add_child(money_l)
	var body := UiKit.hbox(14)
	v.add_child(body)
	grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(UiKit.scroll(grid, Vector2(700, 470)))
	var side := UiKit.panel(Vector2(230, 0))
	side.add_theme_stylebox_override("panel", UiKit.box(UiKit.DARK2, 14))
	body.add_child(side)
	stock_box = UiKit.vbox(6)
	side.add_child(stock_box)
	v.add_child(UiKit.button("Fermer", close, 200))
	_refresh()


func _refresh() -> void:
	money_l.text = "%d €" % session.economy.money(ch.id)
	for c in grid.get_children():
		c.queue_free()
	for id in Data.items:
		var it: Dictionary = Data.items[id]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiKit.box(UiKit.DARK2, 14, 1, Color(1, 1, 1, 0.08)))
		card.custom_minimum_size = Vector2(335, 150)
		grid.add_child(card)
		var h := UiKit.hbox(10)
		card.add_child(h)
		h.add_child(UiKit.icon(id, 64))
		var cv := UiKit.vbox(2)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(cv)
		var t := UiKit.label("%s — %d €" % [it.name, int(it.price)], 18, UiKit.TEXT, true)
		cv.add_child(t)
		var d := UiKit.label(String(it.desc), 13, UiKit.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(d)
		var e := UiKit.label("Effet : " + String(it.effect), 13, Color(0.75, 0.9, 1.0))
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(e)
		var why := session.economy.can_buy(ch.id, id)
		var b := UiKit.button("Acheter" if why == "" else why, func(): _buy(id), 0, 15)
		b.custom_minimum_size = Vector2(0, 36)
		b.disabled = why != ""
		cv.add_child(b)
	for c in stock_box.get_children():
		c.queue_free()
	stock_box.add_child(UiKit.label("Tes gadgets en stock", 17, UiKit.YELLOW, true))
	var st: Dictionary = session.economy.stock.get(ch.id, {})
	var any := false
	for id in st:
		if Data.items.get(id, {}).get("kind", "") in ["cosmetic", "passive", "coop"]:
			stock_box.add_child(UiKit.label("✔ " + Data.item_name(id), 14, UiKit.GOOD))
			continue
		any = true
		var b2 := UiKit.button("%s ×%d → poche" % [Data.item_name(id), int(st[id])], func():
			session.request_action(ch, ch.id, "take_stock", {"item": id})
			_refresh(), 0, 14)
		b2.custom_minimum_size = Vector2(0, 40)
		stock_box.add_child(b2)
	if not any:
		stock_box.add_child(UiKit.label("Rien en réserve.", 14, UiKit.MUTED))
	stock_box.add_child(UiKit.label("Poches : %d/%d" % [ch.items.size(), Character.MAX_POCKET + (2 if "sac_sport" in ch.passive else 0)], 14, UiKit.MUTED))


func _buy(id: String) -> void:
	var r := session.request_action(ch, ch.id, "buy", {"item": id})
	if session.mode == "client":
		get_tree().create_timer(0.3).timeout.connect(_refresh)
	elif r.get("ok", false):
		_refresh()
	else:
		SoundFx.ui("ui_error")


func close() -> void:
	if is_queued_for_deletion():
		return
	ChoicePanel.open_count = maxi(0, ChoicePanel.open_count - 1)
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
