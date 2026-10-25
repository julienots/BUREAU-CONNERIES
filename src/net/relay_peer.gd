class_name RelayPeer
extends MultiplayerPeerExtension
## Internet play without a server of our own: every player keeps one WebSocket to a free
## public MQTT broker, and game packets travel as MQTT messages on topics derived from the
## room code. The hosting player is peer 1 (the authoritative server); the others are
## clients. Plugs into Godot's high-level multiplayer like ENet, so NetSync is unchanged.
##
## Topics:  <PREFIX>r/<CODE>/1     -> the host          <PREFIX>r/<CODE>/<id>  -> one client
##          <PREFIX>r/<CODE>/all   -> every client      <PREFIX>rooms/<CODE>   -> public room info (retained)

signal status_text(text: String)

const PREFIX := "officemayhem/v1/"
## Public brokers, tried in order (wss = TLS on top of HTTPS-like ports).
const BROKERS := ["wss://broker.emqx.io:8084/mqtt", "wss://broker.hivemq.com:8884/mqtt", "wss://test.mosquitto.org:8081/mqtt"]
const HELLO_WAIT := 7.0
const TIMEOUT := 15.0

enum { K_DATA, K_HELLO, K_WELCOME, K_BYE, K_PING, K_REFUSED }

var mq: MqttWs
var code := ""
var server := false
var my_id := 1
var urls: Array = []
var url_i := 0
var last_error := ""
var max_peers := 10
var room_info: Dictionary = {}       # host: last public announcement

var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _target := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _channel := 0
var _refuse := false
var _queue: Array = []               # [from, channel, mode, data]
var _last: Array = [1, 0, MultiplayerPeer.TRANSFER_MODE_RELIABLE, PackedByteArray()]
var peers: Dictionary = {}           # host: id -> last time heard
var _server_seen := 0.0
var _hello_t := 0.0
var _hello_left := 0.0
var _ping_t := 0.0
var _announce_t := 0.0
var _clock := 0.0
var _last_ms := 0


static func broker_list() -> Array:
	var custom := Net.arg("relay", String(Settings.get_v("relay_url")) if Settings.values.has("relay_url") else "")
	return [custom] if custom != "" else BROKERS.duplicate()


func create_server(p_code: String, p_urls: Array, p_max := 10) -> int:
	server = true
	my_id = 1
	code = p_code.to_upper()
	max_peers = p_max
	return _start(p_urls)


func create_client(p_code: String, p_urls: Array) -> int:
	server = false
	code = p_code.strip_edges().to_upper()
	my_id = 2 + (randi() % 2000000000)
	return _start(p_urls)


func _start(p_urls: Array) -> int:
	urls = p_urls
	url_i = 0
	_last_ms = Time.get_ticks_msec()
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	return _open_broker()


func _open_broker() -> int:
	if url_i >= urls.size():
		_fail("Aucun relais Internet joignable (vérifie ta connexion)." if server else "Partie introuvable : vérifie le code (ou ta connexion).")
		return ERR_CANT_CONNECT
	mq = MqttWs.new()
	mq.connected.connect(_on_mq_connected)
	mq.disconnected.connect(_on_mq_disconnected)
	mq.message.connect(_on_message)
	status_text.emit("Connexion au relais %d/%d…" % [url_i + 1, urls.size()])
	var err := mq.open(String(urls[url_i]), "om-%s-%d" % [code, my_id])
	if err != OK:
		url_i += 1
		return _open_broker()
	return OK


func _base() -> String:
	return PREFIX + "r/" + code + "/"


func _fail(msg: String) -> void:
	last_error = msg
	status_text.emit(msg)
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED


func _on_mq_connected() -> void:
	if server:
		mq.subscribe([_base() + "1"])
		_status = MultiplayerPeer.CONNECTION_CONNECTED
		status_text.emit("Partie ouverte sur Internet.")
		if not room_info.is_empty():
			announce(room_info)
	else:
		mq.subscribe([_base() + str(my_id), _base() + "all"])
		_hello_left = HELLO_WAIT
		_hello_t = 0.0
		status_text.emit("Recherche de la partie %s…" % code)


func _on_mq_disconnected(reason: String) -> void:
	if _status == MultiplayerPeer.CONNECTION_CONNECTING:
		url_i += 1   # this broker is unreachable (or the room is not there): try the next one
		_open_broker()
		return
	if _status == MultiplayerPeer.CONNECTION_CONNECTED:
		_fail("Connexion Internet perdue (%s)." % reason)
		if server:
			for id in peers.keys():
				peer_disconnected.emit(id)
			peers.clear()


# ------------------------------------------------------------------ packets
func _pack(kind: int, payload := PackedByteArray(), channel := 0, mode := 0) -> PackedByteArray:
	var flags := 0
	var body := payload
	if payload.size() > 256:
		var z := payload.compress(FileAccess.COMPRESSION_ZSTD)
		if z.size() < payload.size():
			body = z
			flags = 1
	var out := PackedByteArray([kind, 0, 0, 0, 0, channel, mode, flags, 0, 0, 0, 0])
	out.encode_u32(1, my_id)
	out.encode_u32(8, payload.size())
	out.append_array(body)
	return out


func _send_to(id: int, kind: int, payload := PackedByteArray(), channel := 0, mode := 0) -> void:
	mq.publish(_base() + ("all" if id == 0 else str(id)), _pack(kind, payload, channel, mode))


func _on_message(topic: String, data: PackedByteArray) -> void:
	if not topic.begins_with(_base()) or data.size() < 12:
		return
	var kind := data[0]
	var from := data.decode_u32(1)
	if from == my_id:
		return
	var payload := data.slice(12)
	if data[7] & 1:
		payload = payload.decompress(data.decode_u32(8), FileAccess.COMPRESSION_ZSTD)
	if server:
		match kind:
			K_HELLO:
				if peers.has(from):
					_send_to(from, K_WELCOME)
				elif _refuse or peers.size() >= max_peers:
					_send_to(from, K_REFUSED)
				else:
					peers[from] = _clock
					_send_to(from, K_WELCOME)
					peer_connected.emit(from)
			K_BYE:
				if peers.erase(from):
					peer_disconnected.emit(from)
			K_DATA:
				if peers.has(from):
					peers[from] = _clock
					_queue.append([from, data[5], data[6], payload])
			K_PING:
				if peers.has(from):
					peers[from] = _clock
		return
	# client side: only the host (id 1) talks to us
	if from != 1:
		return
	_server_seen = _clock
	match kind:
		K_WELCOME:
			if _status == MultiplayerPeer.CONNECTION_CONNECTING:
				_status = MultiplayerPeer.CONNECTION_CONNECTED
				status_text.emit("Connecté à la partie %s." % code)
				peer_connected.emit(1)
		K_REFUSED:
			_fail("La partie est pleine ou déjà commencée.")
			mq.close()
		K_BYE:
			_fail("L'hôte a fermé la partie.")
		K_DATA:
			if _status == MultiplayerPeer.CONNECTION_CONNECTED:
				_queue.append([1, data[5], data[6], payload])


## Host: publishes (retained) the public room info so others can list it.
func announce(info: Dictionary) -> void:
	room_info = info
	if not server or mq == null or not mq.is_ready():
		return
	if info.get("public", true):
		var d := info.duplicate()
		d["t"] = Time.get_unix_time_from_system()
		mq.publish(PREFIX + "rooms/" + code, JSON.stringify(d).to_utf8_buffer(), true)
	else:
		mq.publish(PREFIX + "rooms/" + code, PackedByteArray(), true)


# ------------------------------------------------------------------ MultiplayerPeerExtension
func _poll() -> void:
	var ms := Time.get_ticks_msec()
	var dt := (ms - _last_ms) / 1000.0
	_last_ms = ms
	_clock += dt
	if mq == null:
		return
	mq.poll(dt)
	if not mq.is_ready():
		return
	_ping_t += dt
	if server:
		if _ping_t > 2.0:
			_ping_t = 0.0
			if not peers.is_empty():
				_send_to(0, K_PING)
		for id in peers.keys():
			if _clock - float(peers[id]) > TIMEOUT:
				peers.erase(id)
				peer_disconnected.emit(id)
		_announce_t += dt
		if _announce_t > 30.0 and not room_info.is_empty():
			_announce_t = 0.0
			announce(room_info)
	elif _status == MultiplayerPeer.CONNECTION_CONNECTING:
		_hello_t -= dt
		_hello_left -= dt
		if _hello_t <= 0.0:
			_hello_t = 1.0
			_send_to(1, K_HELLO)
		if _hello_left <= 0.0:
			# nobody answered on this broker: try the next one
			mq.close()
			url_i += 1
			_open_broker()
	elif _status == MultiplayerPeer.CONNECTION_CONNECTED:
		if _ping_t > 2.0:
			_ping_t = 0.0
			_send_to(1, K_PING)
		if _clock - _server_seen > TIMEOUT:
			_fail("L'hôte ne répond plus.")


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if mq == null or not mq.is_ready() or _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if not server:
		_send_to(1, K_DATA, buffer, _channel, _mode)
		return OK
	if _target == 0:
		_send_to(0, K_DATA, buffer, _channel, _mode)
	elif _target > 0:
		if peers.has(_target):
			_send_to(_target, K_DATA, buffer, _channel, _mode)
	else:
		for id in peers:
			if id != -_target:
				_send_to(id, K_DATA, buffer, _channel, _mode)
	return OK


func _get_packet_script() -> PackedByteArray:
	if _queue.is_empty():
		return PackedByteArray()
	_last = _queue.pop_front()
	return _last[3]


func _get_available_packet_count() -> int:
	return _queue.size()


func _get_max_packet_size() -> int:
	return 1 << 18


func _get_packet_peer() -> int:
	return int(_queue[0][0]) if not _queue.is_empty() else int(_last[0])


func _get_packet_channel() -> int:
	return int(_queue[0][1]) if not _queue.is_empty() else int(_last[1])


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return (int(_queue[0][2]) if not _queue.is_empty() else int(_last[2])) as MultiplayerPeer.TransferMode


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode as MultiplayerPeer.TransferMode


func _set_target_peer(peer: int) -> void:
	_target = peer


func _get_unique_id() -> int:
	return my_id


func _is_server() -> bool:
	return server


func _is_server_relay_supported() -> bool:
	return true


func _set_refuse_new_connections(enable: bool) -> void:
	_refuse = enable


func _is_refusing_new_connections() -> bool:
	return _refuse


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status as MultiplayerPeer.ConnectionStatus


func _disconnect_peer(peer: int, _force: bool) -> void:
	if server and peers.erase(peer):
		_send_to(peer, K_BYE)
		peer_disconnected.emit(peer)


func _close() -> void:
	if mq and mq.is_ready():
		if server:
			mq.publish(PREFIX + "rooms/" + code, PackedByteArray(), true)
			_send_to(0, K_BYE)
		else:
			_send_to(1, K_BYE)
		mq.close()
	peers.clear()
	_queue.clear()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
