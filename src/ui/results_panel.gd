class_name ResultsPanel
extends Control
## End-of-day screen (solo): verdict, missions, money, productivity, sanctions, stats.

signal next_day
signal to_menu


static func open(parent: Control, r: Dictionary) -> ResultsPanel:
	var rp := ResultsPanel.new()
	rp.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(rp)
	rp._build(r)
	return rp


func _build(r: Dictionary) -> void:
	ChoicePanel.open_count += 1
	theme = UiKit.theme()
	var p := UiKit.panel(Vector2(760, 0))
	UiKit.center_modal(self, p)
	var v := UiKit.vbox(8)
	p.add_child(v)
	var title := "JOURNÉE RÉUSSIE !"
	var col := UiKit.GOOD
	if r.get("fired", false):
		title = "RENVOYÉ POUR LA JOURNÉE"
		col = UiKit.BAD
	elif not r.get("won", false):
		title = "JOURNÉE RATÉE"
		col = UiKit.WARN
	v.add_child(UiKit.label(title, 40, col, true))
	v.add_child(UiKit.label("Directeur du jour : %s" % r.get("profile", ""), 16, UiKit.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	v.add_child(grid)
	for row in [["Missions", "%d / %d" % [r.missions_done, r.missions_total]], ["Défis", str(r.side_done)], ["Productivité", "%d %%" % r.productivity],
			["Salaire", "+%d €" % r.salary], ["Primes de bêtises", "+%d €" % r.earned], ["Amendes", "-%d €" % r.fines],
			["Avertissements", "%d / 3" % r.warnings], ["Bêtises", str(r.pranks)], ["Pris sur le fait", str(r.caught)], ["Chutes provoquées", str(r.falls)],
			["Argent total", "%d €" % r.money], ["Score", str(r.score)]]:
		grid.add_child(UiKit.label(row[0], 18, UiKit.MUTED))
		grid.add_child(UiKit.label(row[1], 18, UiKit.TEXT))
	for m in r.get("missions", []):
		v.add_child(UiKit.label(("✔ " if m.done else "✘ ") + String(m.title), 16, UiKit.GOOD if m.done else UiKit.MUTED))
	if not r.get("won", false):
		var why := UiKit.label("Pour réussir : au moins 2 missions, 35 % de productivité et moins de 3 avertissements. Revanche demain !", 15, UiKit.WARN)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size = Vector2(700, 0)
		v.add_child(why)
	var h := UiKit.hbox(12)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	h.add_child(UiKit.button("Journée suivante" if r.get("won", false) else "Revanche", func(): next_day.emit(), 280))
	h.add_child(UiKit.button("Menu principal", func(): to_menu.emit(), 240))
	SoundFx.ui("mission_complete" if r.get("won", false) else "warning_sting")
