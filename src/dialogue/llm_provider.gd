class_name LlmProvider
extends Node
## OPTIONAL local language model (e.g. Ollama running a ~0.5–1.5 B model on the player's
## machine). Disabled by default. Never downloads anything, never blocks the simulation:
## requests are asynchronous, time out after a few seconds, and results only top up the
## Barks pool. If the endpoint is missing or slow, the game silently keeps using templates.
##
## Rough requirements for a useful local model: 0.5B params ≈ 0.4 GB disk / 1 GB RAM,
## 1.5B ≈ 1 GB disk / 2 GB RAM. Desktop only in practice; not recommended on phones.

var barks: Barks
var _http: HTTPRequest
var _busy := false
var _cooldown := 0.0
var _failures := 0
var _queue: Array[String] = ["chat", "gossip", "react_fall_other", "boss_patrol", "witness_prank"]

const PROMPTS := {
	"chat": "Écris UNE courte réplique drôle (max 12 mots) d'un employé de bureau qui papote avec un collègue. Réponds uniquement par la réplique.",
	"gossip": "Écris UNE courte phrase de commérage de bureau absurde (max 14 mots). Réponds uniquement par la phrase.",
	"react_fall_other": "Écris UNE courte réaction moqueuse (max 8 mots) quand un collègue tombe par terre au bureau.",
	"boss_patrol": "Écris UNE courte phrase (max 10 mots) d'un patron autoritaire et ridicule qui surveille ses employés.",
	"witness_prank": "Écris UNE courte réaction (max 8 mots) d'un employé qui vient de voir une blague de bureau.",
}


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 6.0
	add_child(_http)
	_http.request_completed.connect(_on_done)


func enabled() -> bool:
	return bool(Settings.get_v("llm_enabled")) and _failures < 3


func _process(delta: float) -> void:
	if not enabled() or _busy or barks == null:
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = 8.0
	var cat: String = _queue[randi() % _queue.size()]
	if barks.generated_count(cat) >= 8:
		return
	var body := JSON.stringify({"model": Settings.get_v("llm_model"), "prompt": PROMPTS[cat], "stream": false,
		"options": {"num_predict": 40, "temperature": 1.0}})
	_busy = true
	set_meta("cat", cat)
	var err := _http.request(String(Settings.get_v("llm_endpoint")), ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		_failures += 1


func _on_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_failures += 1
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var text := String(parsed.get("response", "")).strip_edges().replace("\"", "").replace("«", "").replace("»", "")
	text = text.split("\n")[0]
	barks.add_generated(String(get_meta("cat", "chat")), text)
