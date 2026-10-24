class_name Tutorial
extends Node
## Short interactive tutorial for the first day: move, work, prank, buy, suspicion.
## Each step completes on a real game event.

var session: Session
var hud: Hud
var ch: Character
var step := 0
var _start := Vector3.ZERO
var _t := 0.0
const STEPS := [
	"Bienvenue chez SuperEssence Corp ! Déplace-toi (ZQSD/WASD ou joystick) et regarde autour de toi avec la souris.",
	"Va à ton bureau (au fond à gauche) et vise ton ordinateur : « Travailler » fait monter ta productivité.",
	"Tes OBJECTIFS SECRETS sont à gauche. Réalise une bêtise… sans que le directeur te voie !",
	"Sur ton PC, la boutique SuperAmazone vend des gadgets. Achètes-en un.",
	"Écoute bien : les pas du directeur font « clac clac ». Ton niveau de soupçon est en haut à droite. Bonne journée !",
]


func setup(s: Session, h: Hud, c: Character) -> void:
	session = s
	hud = h
	ch = c
	_start = c.global_position
	session.game_event_emitted.connect(_on_event)
	_show()


func _show() -> void:
	if step < STEPS.size():
		hud.notify("Tuto %d/%d — %s" % [step + 1, STEPS.size(), STEPS[step]], "event")


func _advance() -> void:
	step += 1
	_t = 0.0
	if step >= STEPS.size():
		Settings.set_v("tutorial_done", true)
		queue_free()
		return
	_show()


func _process(delta: float) -> void:
	_t += delta
	if step == 0 and ch.global_position.distance_to(_start) > 4.0:
		_advance()
	elif step == 4 and _t > 12.0:
		_advance()
	elif _t > 30.0:
		_t = 0.0
		_show()


func _on_event(type: String, d: Dictionary) -> void:
	match step:
		1:
			if type == "action" and d.get("action", "") in ["work_done", "work"] and d.get("actor", "") == ch.id:
				_advance()
		2:
			if type == "prank" and d.get("actor", "") == ch.id:
				_advance()
		3:
			if type == "action" and String(d.get("action", "")) == "buy" or (type == "bought" and d.get("actor", "") == ch.id):
				_advance()
