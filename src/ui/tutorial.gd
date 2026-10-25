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
const TOUCH_STEPS := [
	"Bienvenue chez SuperEssence Corp ! Pose le pouce à GAUCHE de l'écran pour marcher, glisse à DROITE pour tourner la caméra.",
	"Va à ton bureau (panneau jaune « TON BUREAU »), vise l'ordinateur et appuie sur le gros bouton rond : « Travailler ».",
	"Ta MISSION est en haut (touche-la pour voir la liste). La jauge « Le chef » montre ce qu'il pense de toi. Fais une bêtise sans être vu !",
	"Bouton BOUTIQUE en haut : « Farces & Attrapes » pour embêter les collègues et toucher des primes. Achète un objet.",
	"Les pas du chef font « clac clac ». Tes soupçons sont en haut à droite. Pause = en haut à droite. Bonne journée !",
]
const STEPS := [
	"Bienvenue chez SuperEssence Corp ! Déplace-toi (ZQSD/WASD ou joystick) et regarde autour de toi avec la souris.",
	"Va à ton bureau (panneau jaune « TON BUREAU ») et vise ton ordinateur : « Travailler » fait monter ta productivité.",
	"Ta MISSION est en haut (O pour la liste). La jauge « Le chef » montre ce qu'il pense de toi. Réalise une bêtise… sans que le directeur te voie !",
	"Boutique : touche B (ou ton PC). « Farces & Attrapes » rapporte des primes à chaque farce réussie. Achète un objet.",
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
	var steps: Array = TOUCH_STEPS if Settings.use_touch() else STEPS
	if step < steps.size():
		hud.notify("Tuto %d/%d — %s" % [step + 1, steps.size(), steps[step]], "event")


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
