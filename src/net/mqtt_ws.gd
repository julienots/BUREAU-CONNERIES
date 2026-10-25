class_name MqttWs
extends RefCounted
## Minimal MQTT 3.1.1 client over WebSocket (QoS 0 only): enough to use a free public
## broker as a message relay between players, so online games need no server of our own.
## Call poll() every frame. Payloads are raw bytes.

signal connected
signal disconnected(reason: String)
signal message(topic: String, payload: PackedByteArray)

enum { IDLE, OPENING, HANDSHAKE, READY, CLOSED }

const KEEPALIVE := 30

var url := ""
var state := IDLE
var client_id := ""
var _ws := WebSocketPeer.new()
var _buf := PackedByteArray()
var _ping_t := 0.0
var _open_t := 0.0
var _next_pid := 1


func open(p_url: String, p_client_id: String) -> int:
	url = p_url
	client_id = p_client_id
	_ws = WebSocketPeer.new()
	_ws.supported_protocols = PackedStringArray(["mqtt"])
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	_ws.max_queued_packets = 4096
	var tls: TLSOptions = TLSOptions.client() if url.begins_with("wss://") else null
	var err := _ws.connect_to_url(url, tls)
	if err != OK:
		state = CLOSED
		return err
	state = OPENING
	_open_t = 0.0
	_buf.clear()
	return OK


func close() -> void:
	if state == READY:
		_ws.send(PackedByteArray([0xE0, 0x00]), WebSocketPeer.WRITE_MODE_BINARY)
	if state != IDLE and state != CLOSED:
		_ws.close()
	state = CLOSED


func is_ready() -> bool:
	return state == READY


func poll(delta: float) -> void:
	if state == IDLE or state == CLOSED:
		return
	_ws.poll()
	var ws_state := _ws.get_ready_state()
	if ws_state == WebSocketPeer.STATE_CLOSED:
		var was := state
		state = CLOSED
		disconnected.emit("fermé (%d %s)" % [_ws.get_close_code(), _ws.get_close_reason()] if was == READY else "connexion impossible")
		return
	if state == OPENING:
		_open_t += delta
		if ws_state == WebSocketPeer.STATE_OPEN:
			_send_connect()
			state = HANDSHAKE
		elif _open_t > 10.0:
			_ws.close()
			state = CLOSED
			disconnected.emit("délai dépassé")
		return
	while _ws.get_available_packet_count() > 0:
		_buf.append_array(_ws.get_packet())
	_parse()
	if state == READY:
		_ping_t += delta
		if _ping_t > KEEPALIVE * 0.5:
			_ping_t = 0.0
			_ws.send(PackedByteArray([0xC0, 0x00]), WebSocketPeer.WRITE_MODE_BINARY)


func subscribe(topics: Array) -> void:
	var body := PackedByteArray()
	_put_u16(body, _pid())
	for t in topics:
		_put_str(body, String(t))
		body.append(0)   # QoS 0
	_send_packet(0x82, body)


func unsubscribe(topics: Array) -> void:
	var body := PackedByteArray()
	_put_u16(body, _pid())
	for t in topics:
		_put_str(body, String(t))
	_send_packet(0xA2, body)


func publish(topic: String, payload: PackedByteArray, retain := false) -> void:
	if state != READY:
		return
	var body := PackedByteArray()
	_put_str(body, topic)
	body.append_array(payload)
	_send_packet(0x30 | (0x01 if retain else 0x00), body)


# ------------------------------------------------------------------ protocol
func _send_connect() -> void:
	var body := PackedByteArray()
	_put_str(body, "MQTT")
	body.append(4)              # protocol level 3.1.1
	body.append(0x02)           # clean session
	_put_u16(body, KEEPALIVE)
	_put_str(body, client_id)
	_send_packet(0x10, body)


func _send_packet(header: int, body: PackedByteArray) -> void:
	var pkt := PackedByteArray([header])
	var n := body.size()
	while true:
		var b := n % 128
		n = n / 128
		if n > 0:
			b |= 0x80
		pkt.append(b)
		if n == 0:
			break
	pkt.append_array(body)
	_ws.send(pkt, WebSocketPeer.WRITE_MODE_BINARY)


func _parse() -> void:
	while _buf.size() >= 2:
		# remaining length (variable length encoding, up to 4 bytes)
		var mult := 1
		var length := 0
		var i := 1
		var complete := false
		while i < _buf.size() and i <= 4:
			var b := _buf[i]
			length += (b & 0x7F) * mult
			mult *= 128
			i += 1
			if b & 0x80 == 0:
				complete = true
				break
		if not complete or _buf.size() < i + length:
			return   # wait for the rest
		var header := _buf[0]
		var kind := header >> 4
		var body := _buf.slice(i, i + length)
		_buf = _buf.slice(i + length)
		match kind:
			2:  # CONNACK
				if body.size() >= 2 and body[1] == 0:
					state = READY
					_ping_t = 0.0
					connected.emit()
				else:
					state = CLOSED
					_ws.close()
					disconnected.emit("refusé par le relais (%d)" % (body[1] if body.size() > 1 else -1))
			3:  # PUBLISH (QoS 0 expected)
				if body.size() < 2:
					continue
				var tl := (body[0] << 8) | body[1]
				var topic := body.slice(2, 2 + tl).get_string_from_utf8()
				var off := 2 + tl
				if (header >> 1) & 0x03 > 0:
					off += 2   # packet identifier (only present for QoS 1/2)
				message.emit(topic, body.slice(off))
			_:
				pass   # SUBACK, UNSUBACK, PINGRESP: nothing to do


func _pid() -> int:
	_next_pid = (_next_pid % 65535) + 1
	return _next_pid


static func _put_u16(b: PackedByteArray, v: int) -> void:
	b.append((v >> 8) & 0xFF)
	b.append(v & 0xFF)


static func _put_str(b: PackedByteArray, s: String) -> void:
	var u := s.to_utf8_buffer()
	_put_u16(b, u.size())
	b.append_array(u)
