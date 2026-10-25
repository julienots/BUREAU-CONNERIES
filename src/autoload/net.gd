extends Node
## Network transport (ENet). Owns the peer lifecycle only; gameplay messages live in
## NetSync (in-game, same node path on server and clients) and MasterClient (lobby list).
##
## Topologies:
##  - Dedicated room server: `godot --headless -- --server --port=24681 [--code=ABCD]`
##  - Master (room list + invite codes, spawns room servers): `godot --headless -- --master`
##  - LAN host: a player hosts from the menu (server + local player in one process).
##  - Internet (no server of ours): a player hosts through a public MQTT relay, the others
##    join with the room code (RelayPeer). Also usable headless: --server --relay=URL.

signal connected
signal connection_failed
signal disconnected
signal peer_joined(id: int)
signal peer_left(id: int)

const DEFAULT_PORT := 24680
const MAX_CLIENTS := 10

var peer: MultiplayerPeer           # ENetMultiplayerPeer (LAN / dedicated) or RelayPeer (Internet)
var relay_status := ""              # last message from the Internet relay (shown in the lobby)
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
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(port, max_clients)
	if err != OK:
		return err
	peer = enet
	multiplayer.multiplayer_peer = peer
	role = "host" if as_player else "server"
	return OK


func join(address: String, port: int) -> int:
	leave()
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(address, port)
	if err != OK:
		return err
	peer = enet
	multiplayer.multiplayer_peer = peer
	role = "client"
	return OK


## Internet game through the public relay. `as_player`: the host also plays (phone host).
func host_relay(code: String, as_player := true, max_clients := MAX_CLIENTS) -> int:
	leave()
	var rp := RelayPeer.new()
	rp.status_text.connect(func(t): relay_status = t)
	var err := rp.create_server(code, RelayPeer.broker_list(), max_clients)
	if err != OK:
		relay_status = rp.last_error
		return err
	peer = rp
	multiplayer.multiplayer_peer = rp
	role = "host" if as_player else "server"
	room_code = rp.code
	return OK


func join_relay(code: String) -> int:
	leave()
	var rp := RelayPeer.new()
	rp.status_text.connect(func(t): relay_status = t)
	var err := rp.create_client(code, RelayPeer.broker_list())
	if err != OK:
		relay_status = rp.last_error
		return err
	peer = rp
	multiplayer.multiplayer_peer = rp
	role = "client"
	room_code = rp.code
	return OK


func is_relay() -> bool:
	return peer is RelayPeer


## Host on the relay: is the room reachable yet?
func relay_ready() -> bool:
	return peer is RelayPeer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


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
