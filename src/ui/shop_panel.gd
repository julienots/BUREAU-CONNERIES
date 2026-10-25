class_name ShopPanel
extends Control
## Two shops in one panel:
##  - "SuperAmazone" : gadgets & cosmetics
##  - "Farces & Attrapes" : funny prank items that pay a bonus every time they work
## In game the purchase is validated by the session/economy (money, level, uniqueness);
## from the main menu (no session) items go straight to the saved stock.

signal closed

var session: Session
var ch: Character
var economy: Economy
var grid: GridContainer
var money_l: Label
var stock_box: VBoxContainer
var tab := "farces"
var _tab_btns: Dictionary = {}
var _title: Label


static func open(parent: Control, s: Session, c: Character, start_tab := "farces") -> ShopPanel:
	var sp := ShopPanel.new()
	sp.session = s
	sp.ch = c
	sp.tab = start_tab
	sp.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(sp)
	sp._build()
	return sp


func _owner_id() -> String:
	return ch.id if ch else "player"


func _build() -> void:
	ChoicePanel.open_count += 1
	theme = UiKit.theme()
	if session:
		economy = session.economy
	else:
		economy = Economy.new()
		economy.setup_solo("player")
	var p := UiKit.panel(Vector2(1000, 620))
	UiKit.center_modal(self, p)
	var v := UiKit.vbox(8)
	p.add_child(v)
	var head := UiKit.hbox(10)
	v.add_child(head)
	_title = UiKit.label("", 32, UiKit.YELLOW, true)
	head.add_child(_title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	money_l = UiKit.label("", 30, UiKit.YELLOW, true)
	head.add_child(money_l)
	var tabs := UiKit.hbox(8)
	v.add_child(tabs)
	for t in [["farces", "Farces & Attrapes"], ["gadgets", "SuperAmazone (gadgets)"]]:
		var b := UiKit.button(t[1], func():
			tab = t[0]
			_refresh(), 330, 20)
		b.custom_minimum_size.y = 56
		tabs.add_child(b)
		_tab_btns[t[0]] = b
	tabs.add_child(UiKit.button("Fermer", close, 160, 20))
	var body := UiKit.hbox(12)
	v.add_child(body)
	grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(UiKit.scroll(grid, Vector2(730, 470)))
	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", UiKit.box(UiKit.DARK2, 14))
	side.custom_minimum_size = Vector2(230, 0)
	body.add_child(side)
	stock_box = UiKit.vbox(6)
	side.add_child(UiKit.scroll(stock_box, Vector2(200, 450)))
	_refresh()


func _refresh() -> void:
	_title.text = "Farces & Attrapes" if tab == "farces" else "SuperAmazone"
	for k in _tab_btns:
		(_tab_btns[k] as Button).modulate = UiKit.YELLOW if k == tab else Color.WHITE
	money_l.text = "%d €" % economy.money(_owner_id())
	for c in grid.get_children():
		c.queue_free()
	for id in Data.items:
		var it: Dictionary = Data.items[id]
		if String(it.get("shop", "gadgets")) != tab:
			continue
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiKit.box(UiKit.DARK2, 14, 1, Color(1, 1, 1, 0.08)))
		card.custom_minimum_size = Vector2(355, 170)
		grid.add_child(card)
		var h := UiKit.hbox(10)
		card.add_child(h)
		h.add_child(UiKit.icon(id, 72))
		var cv := UiKit.vbox(2)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(cv)
		cv.add_child(UiKit.label("%s — %d €" % [it.name, int(it.price)], 19, UiKit.TEXT, true))
		var d := UiKit.label(String(it.desc), 14, UiKit.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(d)
		var e := UiKit.label(String(it.effect), 14, Color(0.75, 0.92, 1.0))
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(e)
		var why := economy.can_buy(_owner_id(), id)
		var b := UiKit.button("Acheter" if why == "" else why, func(): _buy(id), 0, 17)
		b.custom_minimum_size = Vector2(0, 52)
		b.disabled = why != ""
		cv.add_child(b)
	for c in stock_box.get_children():
		c.queue_free()
	stock_box.add_child(UiKit.label("Ton stock", 18, UiKit.YELLOW, true))
	var st: Dictionary = economy.stock.get(_owner_id(), {})
	var any := false
	for id in st:
		var kind: String = Data.items.get(id, {}).get("kind", "")
		if kind in ["cosmetic", "passive", "coop"]:
			stock_box.add_child(UiKit.label("✔ " + Data.item_name(id), 15, UiKit.GOOD))
			continue
		any = true
		if session and ch:
			var b2 := UiKit.button("%s ×%d → poche" % [Data.item_name(id), int(st[id])], func():
				session.request_action(ch, ch.id, "take_stock", {"item": id})
				get_tree().create_timer(0.25).timeout.connect(_refresh), 0, 15)
			b2.custom_minimum_size = Vector2(0, 52)
			stock_box.add_child(b2)
		else:
			stock_box.add_child(UiKit.label("%s ×%d" % [Data.item_name(id), int(st[id])], 15))
	if not any:
		stock_box.add_child(UiKit.label("Rien en réserve.", 14, UiKit.MUTED))
	if ch:
		stock_box.add_child(UiKit.label("Poches : %d/%d" % [ch.items.size(), Character.MAX_POCKET + (2 if "sac_sport" in ch.passive else 0)], 14, UiKit.MUTED))
	else:
		var hint := UiKit.label("Tes achats t'attendent : ouvre la boutique pendant la journée et mets-les dans ta poche.", 13, UiKit.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(190, 0)
		stock_box.add_child(hint)


func _buy(id: String) -> void:
	if session == null:
		var why := economy.buy("player", id, null)
		if why == "":
			SoundFx.ui("cash_register")
			SaveGame.save_game()
		else:
			SoundFx.ui("ui_error")
		_refresh()
		return
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
