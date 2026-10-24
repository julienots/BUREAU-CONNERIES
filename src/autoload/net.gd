extends Node
## Network transport (ENet). Gameplay messages live in the Session / Lobby nodes; this
## autoload only owns the peer lifecycle. Implemented fully in step 6 (multiplayer).

signal connected
signal connection_failed
signal disconnected
signal peer_joined(id: int)
signal peer_left(id: int)

var peer: ENetMultiplayerPeer


func is_active() -> bool:
	return peer != null


func is_server() -> bool:
	return peer != null and multiplayer.is_server()


func leave() -> void:
	if peer:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
