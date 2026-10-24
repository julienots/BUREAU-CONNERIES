class_name Device
extends Node3D
## Static interactive equipment (PC, phone, drawer, printer, coffee machine, fridge,
## microwave, radio, light switch, whiteboard, planning board, archive shelves...).
## get_actions() is evaluated identically on the authority to validate requests.

var kind := ""
var display := ""
var owner_id := ""
var zone := ""
var state: Dictionary = {}
var screen: MeshInstance3D          # pc / whiteboard / planning surface
var point_offset := Vector3(0, 1.0, 0)
var contents: Array[String] = []     # container: hidden prop ent ids
var _loop: AudioStreamPlayer3D
var _timer := 0.0


func ent_id() -> String:
	return get_meta("ent_id", name)


func display_name() -> String:
	return display


func interact_point() -> Vector3:
	return global_position + global_basis * point_offset


func is_container() -> bool:
	return kind in ["drawer", "fridge", "toilet", "boss_drawer"]


func _sess() -> Node:
	return Game.session


func _process(delta: float) -> void:
	if _sess() == null or not _sess().is_authority():
		return
	match kind:
		"printer":
			if state.get("pages", 0) > 0 and not state.get("jammed", false):
				_timer -= delta
				if _timer <= 0.0:
					_timer = 0.35
					state.pages -= 1
					_sess().eject_sheet(self)
					if state.pages % 6 == 0:
						_sess().emit_sound(interact_point(), 48.0, "paper_eject", state.get("by", ""), ent_id(), "printer")
					if state.pages <= 0:
						_set_loop(false)
						_sess().set_device_state(self)
		"radio":
			if state.get("on", false):
				_timer -= delta
				if _timer <= 0.0:
					_timer = 3.0
					var loud := 72.0 if state.get("loud", false) else 30.0
					_sess().emit_sound(interact_point(), loud, "", state.get("by", "") if state.get("loud", false) else "", ent_id(), "radio")
					if state.get("loud", false):
						_sess().game_event("device_tick", {"device": "radio_loud", "dt": 3.0, "by": state.get("by", "")})
		"microwave":
			if state.get("heating", 0.0) > 0.0:
				state.heating -= delta
				if state.heating <= 0.0:
					_set_loop(false)
					_sess().emit_sound(interact_point(), 40.0, "microwave_ding", "", ent_id())
					_sess().start_smell(interact_point(), state.get("by", ""))
					_sess().set_device_state(self)
		"phone":
			if state.get("ringing", 0.0) > 0.0:
				state.ringing -= delta
				_timer -= delta
				if _timer <= 0.0:
					_timer = 2.8
					_sess().emit_sound(interact_point(), 58.0, "phone_ring", state.get("by", ""), ent_id(), "phone")
				if state.ringing <= 0.0:
					_sess().set_device_state(self)


func _set_loop(on: bool, sfx := "") -> void:
	if on:
		if _loop == null:
			_loop = SoundFx.make_loop_emitter(self, sfx)
			_loop.position = point_offset
		elif sfx != "":
			_loop.stream = SoundFx.sfx_stream(sfx)
		_loop.play()
	elif _loop:
		_loop.stop()


## Visual refresh from `state` (also used by multiplayer clients after a state sync).
func apply_state() -> void:
	match kind:
		"pc":
			if screen == null:
				return
			var tex := "screen_work"
			if state.get("it_down", false):
				tex = "screen_it"
			elif state.get("postits", false):
				tex = "screen_postits"
			elif state.get("wallpaper", "") != "":
				tex = state.wallpaper
			elif state.get("mail", false):
				tex = "screen_mail"
			screen.material_override = Mats.screen(tex)
		"whiteboard":
			if screen:
				screen.material_override = Mats.decal_tex("whiteboard_caricature_albedo" if state.get("caricature", false) else "whiteboard_albedo")
		"planning":
			if screen:
				screen.material_override = Mats.decal_tex("sign_meeting_fake" if state.get("fake", false) else "sign_meeting_ok")
		"printer":
			_set_loop(state.get("pages", 0) > 0 and not state.get("jammed", false), "printer_loop")
		"radio":
			if state.get("on", false):
				if _loop == null:
					_loop = SoundFx.make_loop_emitter(self, "radio_loop", SoundFx.MUSIC_DIR, "Music")
					_loop.position = point_offset
				_loop.volume_db = 6.0 if state.get("loud", false) else -8.0
				_loop.unit_size = 10.0 if state.get("loud", false) else 3.0
				if not _loop.playing:
					_loop.play()
			elif _loop:
				_loop.stop()
		"microwave":
			_set_loop(state.get("heating", 0.0) > 0.0, "microwave_loop")


func get_actions(actor: Node) -> Array:
	var out: Array = []
	var s := _sess()
	var me: String = actor.char_id()
	var mine := owner_id != "" and owner_id == me
	match kind:
		"pc":
			if state.get("it_down", false):
				out.append({"id": "noop", "label": "Ordinateur en redémarrage…", "blocked": "Intervention informatique en cours"})
				return out
			if mine:
				out.append({"id": "work", "label": "Travailler", "time": 0.0, "ui": "work"})
				out.append({"id": "pretend", "label": "Faire semblant de travailler", "time": 0.0})
				out.append({"id": "shop", "label": "Boutique SuperAmazone", "time": 0.0, "ui": "shop"})
				out.append({"id": "call_phone", "label": "Appeler un poste…", "time": 0.0, "ui": "call", "sus": 0.0})
				out.append({"id": "work_done", "hidden": true})
			elif owner_id == "boss":
				out.append({"id": "spy_pc", "label": "Fouiller l'ordinateur du chef", "time": 4.0, "noise": 6.0, "sus": 1.0, "prank": true, "act": "spy", "sev": 3})
			elif owner_id != "":
				var away: bool = s.owner_away(owner_id, global_position)
				var blocked := "" if away else "%s est assis devant." % s.char_name(owner_id)
				if state.get("wallpaper", "") == "":
					out.append({"id": "change_wallpaper", "label": "Changer le fond d'écran", "time": 4.0, "noise": 10.0, "sus": 0.8, "prank": true, "act": "wallpaper", "sev": 2, "blocked": blocked})
				if not state.get("postits", false):
					var b2 := blocked
					if b2 == "" and not actor.has_item("post_its"):
						b2 = "Il te faut des post-it (salle de reprographie)."
					out.append({"id": "post_its", "label": "Couvrir l'écran de post-it", "time": 5.0, "noise": 6.0, "sus": 0.8, "prank": true, "act": "postits", "sev": 2, "blocked": b2})
			if owner_id != "boss":
				out.append({"id": "print_spam", "label": "Imprimer 50 pages", "time": 2.0, "noise": 8.0, "sus": 0.4, "prank": true, "act": "print_spam", "sev": 2,
					"blocked": "" if mine or s.owner_away(owner_id, global_position) else "Quelqu'un utilise ce poste."})
		"phone":
			if state.get("ringing", 0.0) > 0.0:
				out.append({"id": "answer", "label": "Décrocher", "time": 0.5})
		"drawer", "boss_drawer", "fridge", "toilet":
			if kind == "toilet":
				out.append({"id": "use_toilet", "label": "Utiliser", "time": 3.0, "noise": 15.0})
			if not contents.is_empty():
				out.append({"id": "open", "label": "Ouvrir / fouiller", "time": 1.0, "noise": 8.0, "sus": 0.3 if not mine else 0.0})
			if actor.has_method("pocket_items") and not actor.pocket_items().is_empty():
				out.append({"id": "hide", "label": "Cacher un objet ici", "time": 1.5, "noise": 6.0, "sus": 0.5, "ui": "hide"})
			if (kind == "boss_drawer" or kind == "drawer") and actor.has_item("confettis") and not state.get("confetti", false):
				out.append({"id": "confetti", "label": "Piéger avec les confettis", "time": 2.5, "noise": 6.0, "sus": 0.9, "prank": true, "act": "confetti_trap", "sev": 3})
		"printer":
			if state.get("jammed", false):
				out.append({"id": "unjam", "label": "Débloquer l'imprimante", "time": 3.0, "noise": 20.0})
			out.append({"id": "kick_printer", "label": "Donner un coup", "time": 0.0, "noise": 0.0, "sus": 0.2})
		"coffee":
			out.append({"id": "coffee", "label": "Prendre un café", "time": 2.5, "noise": 30.0})
			if not state.get("salted", false):
				out.append({"id": "salt", "label": "Saler la machine", "time": 2.0, "noise": 5.0, "sus": 0.9, "prank": true, "act": "salt_coffee", "sev": 2,
					"blocked": "" if actor.has_item("sel") else "Il te faut la salière (cuisine)."})
		"microwave":
			if state.get("heating", 0.0) <= 0.0:
				out.append({"id": "heat_fish", "label": "Faire chauffer le poisson", "time": 2.0, "noise": 10.0, "sus": 0.7, "prank": true, "act": "heat_fish", "sev": 2,
					"blocked": "" if actor.has_item("poisson") else "Il te faut le poisson (frigo)."})
		"radio":
			if state.get("on", false):
				out.append({"id": "radio_off", "label": "Éteindre la radio", "time": 0.0})
				if not state.get("loud", false):
					out.append({"id": "radio_loud", "label": "Monter le son à fond", "time": 0.0, "sus": 0.5, "act": "radio", "sev": 1})
			else:
				out.append({"id": "radio_on", "label": "Allumer la radio", "time": 0.0})
		"light_switch":
			var on: bool = s.world.zone_lit(state.get("zone", ""))
			out.append({"id": "light_toggle", "label": "Éteindre la lumière" if on else "Allumer la lumière", "time": 0.0, "sus": 0.5 if on else 0.0,
				"act": "lights_off" if on else "", "sev": 2 if on and s.meeting_active else 0, "prank": on and s.meeting_active})
		"whiteboard":
			if state.get("caricature", false):
				out.append({"id": "erase", "label": "Effacer le tableau", "time": 3.0, "noise": 10.0})
			else:
				out.append({"id": "caricature", "label": "Dessiner une caricature du chef", "time": 6.0, "noise": 12.0, "sus": 1.0, "prank": true, "act": "caricature", "sev": 4,
					"blocked": "" if actor.has_item("marqueur") else "Il te faut un marqueur."})
		"planning":
			out.append({"id": "read", "label": "Lire le planning", "time": 0.0})
			if not state.get("fake", false):
				out.append({"id": "fake_planning", "label": "Remplacer par un faux planning", "time": 3.0, "noise": 6.0, "sus": 0.8, "prank": true, "act": "fake_planning", "sev": 2})
		"shelf_files":
			if not state.get("mixed", false):
				out.append({"id": "mix_files", "label": "Mélanger les dossiers", "time": 3.0, "noise": 12.0, "sus": 0.5, "prank": true, "act": "mix_files", "sev": 1})
		"supply":
			out.append({"id": "take_postits", "label": "Prendre des post-it", "time": 1.0, "noise": 4.0,
				"blocked": "" if int(state.get("stock", 3)) > 0 else "Plus de post-it."})
		"water":
			out.append({"id": "drink_water", "label": "Boire un verre d'eau", "time": 2.0, "noise": 20.0})
		"vending":
			out.append({"id": "snack", "label": "Acheter un snack (2 €)", "time": 1.5, "noise": 30.0})
		"sink":
			out.append({"id": "wash", "label": "Se laver les mains", "time": 2.0, "noise": 15.0})
		"notice":
			out.append({"id": "read", "label": "Lire les annonces", "time": 0.0})
	return out


func perform(actor: Node, action: String, params: Dictionary) -> Dictionary:
	var s := _sess()
	var me: String = actor.char_id()
	match action:
		"pretend":
			s.start_pretend(actor, self)
		"work_done":
			return s.work_done(actor, params)
		"call_phone":
			var target: String = params.get("target", "")
			var ph: Device = s.phone_of(target)
			if ph == null:
				return {"ok": false, "msg": "Poste introuvable."}
			ph.state.ringing = 9.0
			ph.state.by = me
			ph._timer = 0.0
			s.game_event("action", {"action": "call_phone", "actor": me, "target": ph.ent_id(), "target_owner": target})
		"answer":
			state.ringing = 0.0
			s.emit_sound(interact_point(), 20.0, "phone_pickup", "", ent_id())
		"change_wallpaper":
			state.wallpaper = ["wall_duck", "wall_potato", "wall_boss", "wall_cat"][randi() % 4]
			s.emit_sound(interact_point(), 12.0, "mouse_click", me, ent_id())
		"post_its":
			if not actor.consume_item("post_its"):
				return {"ok": false, "msg": "Plus de post-it."}
			state.postits = true
		"print_spam":
			var pr: Device = s.find_device("printer")
			if pr == null:
				return {"ok": false, "msg": "Pas d'imprimante."}
			pr.state.pages = int(pr.state.get("pages", 0)) + 50
			pr.state.by = me
			pr.apply_state()
			s.set_device_state(pr)
			s.game_event("printer_spam", {"by": me})
		"spy_pc":
			s.reveal_boss_intel(actor)
		"open":
			return s.open_container(actor, self)
		"hide":
			return s.hide_in_container(actor, self, params.get("item", ""))
		"confetti":
			if not actor.consume_item("confettis"):
				return {"ok": false, "msg": "Pas de confettis."}
			state.confetti = true
			state.by = me
		"use_toilet":
			s.satisfy_need(actor, "bladder")
		"unjam":
			state.jammed = false
			apply_state()
		"kick_printer":
			s.emit_sound(interact_point(), 62.0, "printer_jam", me, ent_id())
			if state.get("jammed", false) and randf() < 0.5:
				state.jammed = false
		"coffee":
			s.emit_sound(interact_point(), 40.0, "coffee_machine", "", ent_id(), "coffee")
			s.give_coffee(actor, self)
		"salt":
			actor.consume_item("sel")
			state.salted = true
			state.by = me
		"heat_fish":
			actor.consume_item("poisson")
			state.heating = 6.0
			state.by = me
		"radio_on":
			state.on = true
			state.loud = false
			state.by = me
			_timer = 0.0
		"radio_off":
			state.on = false
			state.loud = false
		"radio_loud":
			state.loud = true
			state.by = me
			_timer = 0.0
		"light_toggle":
			var z: String = state.get("zone", "")
			s.set_zone_lights(z, not s.world.zone_lit(z), me)
			s.emit_sound(interact_point(), 14.0, "light_switch", "", ent_id())
		"caricature":
			state.caricature = true
			state.by = me
			s.emit_sound(interact_point(), 18.0, "marker_squeak", me, ent_id())
		"erase":
			state.caricature = false
		"fake_planning":
			state.fake = true
			state.by = me
		"read":
			s.notify(actor, "Planning : réunion d'équipe à 10h30 et 15h30, salle Synergie." if kind == "planning" and not state.get("fake", false)
				else ("Le planning dit : réunion REPORTÉE à 16h." if kind == "planning" else "Annonces : « Qui a pris mon yaourt ?? — Gérard »"))
		"mix_files":
			state.mixed = true
			s.emit_sound(interact_point(), 22.0, "paper_rustle", me, ent_id())
		"take_postits":
			if not actor.add_item("post_its"):
				return {"ok": false, "msg": "Inventaire plein."}
			state.stock = int(state.get("stock", 3)) - 1
		"drink_water":
			s.emit_sound(interact_point(), 25.0, "water_glug", "", ent_id())
			s.satisfy_need(actor, "coffee", 0.3)
		"snack":
			if not s.spend(actor, 2):
				return {"ok": false, "msg": "Pas assez d'argent."}
			s.emit_sound(interact_point(), 35.0, "hit_plastic", "", ent_id())
		"wash":
			s.emit_sound(interact_point(), 22.0, "water_glug", "", ent_id())
		_:
			return {"ok": false, "msg": "Action inconnue."}
	apply_state()
	s.set_device_state(self)
	return {"ok": true}
