extends Node
## Network transport (ENet). Owns the peer lifecycle only; gameplay messages live in
## NetSync (in-game, same node path on server and clients) and MasterClient (lobby list).
##
## Topologies:
##  - Dedicated room server: `godot --headless -- --server --port=24681 [--code=ABCD]`
##  - Master (room list + invite codes, spawns room servers): `godot --headless -- --master`
##  - LAN host: a player hosts from the menu (server + local player in one process).

signal connected
signal connection_failed
signal disconnected
signal peer_joined(id: int)
signal peer_left(id: int)

const DEFAULT_PORT := 24680
const MAX_CLIENTS := 10

var peer: ENetMultiplayerPeer
var role := ""                 # "" | server | client | host
var room_code := ""
var token := ""                # reconnection token for this client
var args: Dictionary = {}      # parsed command line (--key=value)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	token = _random_token()
	multiplayer.peer_connected.connect(func(id): peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id): peer_left.emit(id))
	multiplayer.connected_to_server.connect(func(): connected.emit())
	multiplayer.connection_failed.connect(func():
		peer = null
		connection_failed.emit())
	multiplayer.server_disconnected.connect(func():
		peer = null
		disconnected.emit())


func _random_token() -> String:
	var c := Crypto.new()
	return c.generate_random_bytes(12).hex_encode()


func is_active() -> bool:
	return peer != null


func is_server() -> bool:
	return peer != null and multiplayer.is_server()


func host(port: int, max_clients := MAX_CLIENTS, as_player := false) -> int:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	role = "host" if as_player else "server"
	return OK


func join(address: String, port: int) -> int:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	role = "client"
	return OK


func leave() -> void:
	if peer:
		peer.close()
	peer = null
	role = ""
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func my_id() -> int:
	return multiplayer.get_unique_id() if peer else 1


static func make_code() -> String:
	var letters := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var s := ""
	for i in 4:
		s += letters[randi() % letters.length()]
	return s


func arg(key: String, default: String = "") -> String:
	return String(args.get(key, default))
