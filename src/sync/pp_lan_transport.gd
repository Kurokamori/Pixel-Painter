class_name PPLanTransport
extends PPTransport

## Sync over the local network. Fully functional on both Windows and iOS with no
## native code -- Godot's UDP and TCP primitives are all this needs.
##
## Discovery: every device broadcasts a small JSON beacon on UDP :47624 once a
## second and listens on the same port. mDNS/Bonjour would be tidier, but it
## needs a native resolver on iOS; a broadcast beacon works identically on both
## platforms and has no dependencies.
##
## Transfer: the sender opens a TCP connection to the port named in the peer's
## beacon and streams a framed .pxp. TCP is the right call here -- projects are
## megabytes, and re-implementing retransmission over UDP to save a handshake
## would be silly.
##
## Both the send and the receive side are non-blocking state machines polled from
## the main thread, so a 40 MB transfer never stalls a stroke.

const DISCOVERY_PORT: int = 47624
const BEACON_INTERVAL_MS: int = 1000
const CHUNK_SIZE: int = 64 * 1024
const CONNECT_TIMEOUT_MS: int = 8000

enum SendState {
	IDLE,
	CONNECTING,
	SENDING,
	AWAITING_ACK,
}

enum ReceiveState {
	HEADER,
	PAYLOAD,
}


## An inbound TCP connection being read.
class Inbound:
	extends RefCounted

	var stream: StreamPeerTCP = null
	var buffer: PackedByteArray = PackedByteArray()
	var state: ReceiveState = ReceiveState.HEADER
	var header: PPSyncProtocol.Header = null
	var peer: PPSyncPeer = null
	var started_ms: int = 0


## Receiving and sending beacons use *separate* sockets on purpose.
##
## Only one process can bind the discovery port. If a second copy of the app (or
## anything else) already holds it, a single shared socket would take the whole
## transport down with it. Split, a port conflict costs this instance only its
## ability to *see* peers -- it still announces itself, so other devices can still
## find it and send to it.
var _listen_udp: PacketPeerUDP = null
var _beacon_udp: PacketPeerUDP = null
var _server: TCPServer = null
var _tcp_port: int = 0
var _can_discover: bool = false

var _peers: Dictionary[String, PPSyncPeer] = {}
var _inbound: Array[Inbound] = []

var _send_state: SendState = SendState.IDLE
var _send_stream: StreamPeerTCP = null
var _send_peer: PPSyncPeer = null
var _send_bytes: PackedByteArray = PackedByteArray()
var _send_offset: int = 0
var _send_started_ms: int = 0

var _last_beacon_ms: int = 0
var _running: bool = false

## Only a failure to open the listening socket is fatal -- without it we can
## neither be found nor receive. Losing the discovery port is merely degrading,
## so it is a warning: this device still announces itself and still accepts
## transfers, it just cannot list peers of its own.
var _fatal_reason: String = ""
var _warning: String = ""


func get_id() -> StringName:
	return &"lan"


func get_display_name() -> String:
	return "Wi-Fi / LAN"


func is_available() -> bool:
	return _fatal_reason.is_empty()


func get_unavailable_reason() -> String:
	return _fatal_reason


func get_warning() -> String:
	return _warning


func is_busy() -> bool:
	return _send_state != SendState.IDLE


func start() -> Error:
	if _running:
		return OK

	# Bind the receiving TCP socket first: its port goes into the beacon, so we
	# cannot announce ourselves until we know where we are listening.
	_server = TCPServer.new()
	var listen_error: Error = _server.listen(0)
	if listen_error != OK:
		_fatal_reason = "Could not open a listening socket (error %d)." % listen_error
		availability_changed.emit()
		return listen_error
	_tcp_port = _server.get_local_port()

	_beacon_udp = PacketPeerUDP.new()
	_beacon_udp.set_broadcast_enabled(true)
	_beacon_udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)

	_listen_udp = PacketPeerUDP.new()
	_listen_udp.set_broadcast_enabled(true)
	var bind_error: Error = _listen_udp.bind(DISCOVERY_PORT)
	_can_discover = bind_error == OK
	if not _can_discover:
		# Someone else holds the port. We can still announce ourselves and still
		# accept transfers -- we just cannot list peers ourselves.
		_warning = (
			"Discovery port %d is in use, so other devices will not be listed here. "
			% DISCOVERY_PORT
			+ "They can still see this device and send to it."
		)

	_running = true
	_last_beacon_ms = 0
	availability_changed.emit()
	return OK


func stop() -> void:
	if not _running:
		return
	_running = false

	_cancel_send("Transport stopped.")

	for inbound: Inbound in _inbound:
		inbound.stream.disconnect_from_host()
	_inbound.clear()

	if _listen_udp != null:
		_listen_udp.close()
		_listen_udp = null
	if _beacon_udp != null:
		_beacon_udp.close()
		_beacon_udp = null
	if _server != null:
		_server.stop()
		_server = null

	for peer: PPSyncPeer in _peers.values():
		peer_lost.emit(peer)
	_peers.clear()


func poll() -> void:
	if not _running:
		return

	_beacon()
	_receive_beacons()
	_expire_peers()
	_accept_connections()
	_pump_inbound()
	_pump_send()


func get_peers() -> Array[PPSyncPeer]:
	var list: Array[PPSyncPeer] = []
	for peer: PPSyncPeer in _peers.values():
		list.append(peer)
	list.sort_custom(func(a: PPSyncPeer, b: PPSyncPeer) -> bool: return a.name < b.name)
	return list


# --- Discovery --------------------------------------------------------------

func _beacon() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_beacon_ms < BEACON_INTERVAL_MS:
		return
	_last_beacon_ms = now

	var settings: PPSettings = PPSettings.get_instance()
	var payload: Dictionary = {
		"id": settings.device_id,
		"name": settings.device_name,
		"platform": OS.get_name(),
		"port": _tcp_port,
	}
	_beacon_udp.put_packet(JSON.stringify(payload).to_utf8_buffer())


func _receive_beacons() -> void:
	if not _can_discover:
		return

	while _listen_udp.get_available_packet_count() > 0:
		var packet: PackedByteArray = _listen_udp.get_packet()
		var sender_ip: String = _listen_udp.get_packet_ip()

		var data: Dictionary = PPSyncProtocol.parse_json(packet)
		if data.is_empty():
			continue

		var id: String = String(data.get("id", ""))
		if id.is_empty() or id == PPSettings.get_instance().device_id:
			# Our own broadcast comes straight back to us; ignore it.
			continue

		var key: String = "lan:%s" % id
		if _peers.has(key):
			var known: PPSyncPeer = _peers[key]
			known.touch()
			known.address = sender_ip
			known.port = int(data.get("port", known.port))
			known.name = String(data.get("name", known.name))
			continue

		var peer: PPSyncPeer = PPSyncPeer.create(
			id,
			String(data.get("name", "Device")),
			String(data.get("platform", "unknown")),
			&"lan"
		)
		peer.address = sender_ip
		peer.port = int(data.get("port", 0))
		_peers[key] = peer
		peer_found.emit(peer)


func _expire_peers() -> void:
	var dead: Array[String] = []
	for key: String in _peers:
		if _peers[key].is_stale():
			dead.append(key)
	for key: String in dead:
		var peer: PPSyncPeer = _peers[key]
		_peers.erase(key)
		peer_lost.emit(peer)


# --- Receiving --------------------------------------------------------------

func _accept_connections() -> void:
	while _server.is_connection_available():
		var inbound: Inbound = Inbound.new()
		inbound.stream = _server.take_connection()
		inbound.started_ms = Time.get_ticks_msec()
		_inbound.append(inbound)


func _pump_inbound() -> void:
	var finished: Array[Inbound] = []

	for inbound: Inbound in _inbound:
		inbound.stream.poll()
		var status: StreamPeerTCP.Status = inbound.stream.get_status()

		if status != StreamPeerTCP.STATUS_CONNECTED:
			if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
				finished.append(inbound)
			continue

		var available: int = inbound.stream.get_available_bytes()
		if available > 0:
			var result: Array = inbound.stream.get_data(available)
			if result[0] == OK:
				inbound.buffer.append_array(result[1])

		if not _advance_inbound(inbound):
			finished.append(inbound)

	for inbound: Inbound in finished:
		inbound.stream.disconnect_from_host()
		_inbound.erase(inbound)


## Returns false when this connection is done (or broken) and should be dropped.
func _advance_inbound(inbound: Inbound) -> bool:
	while true:
		if inbound.state == ReceiveState.HEADER:
			if inbound.buffer.size() < PPSyncProtocol.HEADER_SIZE:
				return true

			var header: PPSyncProtocol.Header = PPSyncProtocol.parse_header(inbound.buffer)
			if not header.valid:
				# Not one of ours, or corrupt beyond recovery.
				return false

			inbound.header = header
			inbound.state = ReceiveState.PAYLOAD
			continue

		var needed: int = PPSyncProtocol.HEADER_SIZE + inbound.header.length
		if inbound.buffer.size() < needed:
			return true

		var payload: PackedByteArray = inbound.buffer.slice(
			PPSyncProtocol.HEADER_SIZE, needed
		)
		inbound.buffer = inbound.buffer.slice(needed)

		if not _handle_message(inbound, inbound.header, payload):
			return false

		inbound.state = ReceiveState.HEADER
		inbound.header = null

	return true


func _handle_message(
	inbound: Inbound, header: PPSyncProtocol.Header, payload: PackedByteArray
) -> bool:
	match header.type:
		PPSyncProtocol.MessageType.HELLO:
			var data: Dictionary = PPSyncProtocol.parse_json(payload)
			var peer: PPSyncPeer = PPSyncPeer.create(
				String(data.get("id", "unknown")),
				String(data.get("name", "Device")),
				String(data.get("platform", "unknown")),
				&"lan"
			)
			peer.address = inbound.stream.get_connected_host()
			inbound.peer = peer
			return true

		PPSyncProtocol.MessageType.PROJECT:
			if not PPSyncProtocol.verify(header, payload):
				# The bytes arrived damaged; tell the sender rather than opening a
				# corrupt project.
				inbound.stream.put_data(
					PPSyncProtocol.frame_json(
						PPSyncProtocol.MessageType.REFUSE,
						{"reason": "Checksum mismatch."}
					)
				)
				return false

			var from: PPSyncPeer = inbound.peer
			if from == null:
				from = PPSyncPeer.create("unknown", "Unknown Device", "unknown", &"lan")

			inbound.stream.put_data(
				PPSyncProtocol.frame_json(
					PPSyncProtocol.MessageType.ACK, {"ok": true}
				)
			)
			project_received.emit(from, payload)
			return true

	return true


# --- Sending ----------------------------------------------------------------

func send_project(
	peer: PPSyncPeer, bytes: PackedByteArray, project_name: String
) -> Error:
	if not _running:
		return ERR_UNCONFIGURED
	if _send_state != SendState.IDLE:
		return ERR_BUSY
	if peer.address.is_empty() or peer.port <= 0:
		return ERR_INVALID_PARAMETER

	_send_stream = StreamPeerTCP.new()
	var error: Error = _send_stream.connect_to_host(peer.address, peer.port)
	if error != OK:
		_send_stream = null
		return error

	var settings: PPSettings = PPSettings.get_instance()
	var hello: PackedByteArray = PPSyncProtocol.frame_json(
		PPSyncProtocol.MessageType.HELLO,
		{
			"id": settings.device_id,
			"name": settings.device_name,
			"platform": OS.get_name(),
			"project": project_name,
		}
	)
	var project: PackedByteArray = PPSyncProtocol.frame(
		PPSyncProtocol.MessageType.PROJECT, bytes
	)

	_send_bytes = hello
	_send_bytes.append_array(project)
	_send_offset = 0
	_send_peer = peer
	_send_state = SendState.CONNECTING
	_send_started_ms = Time.get_ticks_msec()

	transfer_started.emit(peer, _send_bytes.size())
	return OK


func _pump_send() -> void:
	if _send_state == SendState.IDLE:
		return

	_send_stream.poll()
	var status: StreamPeerTCP.Status = _send_stream.get_status()

	if status == StreamPeerTCP.STATUS_ERROR:
		_cancel_send("Could not reach %s." % _send_peer.name)
		return

	if status == StreamPeerTCP.STATUS_CONNECTING:
		if Time.get_ticks_msec() - _send_started_ms > CONNECT_TIMEOUT_MS:
			_cancel_send("%s did not answer." % _send_peer.name)
		return

	if status != StreamPeerTCP.STATUS_CONNECTED:
		_cancel_send("Connection closed unexpectedly.")
		return

	if _send_state == SendState.CONNECTING:
		_send_state = SendState.SENDING

	if _send_state == SendState.SENDING:
		# Send in chunks so a big project cannot block the frame.
		var remaining: int = _send_bytes.size() - _send_offset
		if remaining > 0:
			var take: int = mini(CHUNK_SIZE, remaining)
			var chunk: PackedByteArray = _send_bytes.slice(
				_send_offset, _send_offset + take
			)

			var result: Array = _send_stream.put_partial_data(chunk)
			if result[0] != OK:
				_cancel_send("Transfer failed.")
				return

			# Advance by what the socket actually accepted, not by what we
			# offered: a full send buffer takes a short write, and treating that
			# as a full one would silently punch a hole in the project.
			var written: int = result[1]
			_send_offset += written
			transfer_progress.emit(_send_peer, _send_offset, _send_bytes.size())
			return

		_send_state = SendState.AWAITING_ACK
		return

	if _send_state == SendState.AWAITING_ACK:
		var available: int = _send_stream.get_available_bytes()
		if available < PPSyncProtocol.HEADER_SIZE:
			# Give the receiver a moment to answer, but do not wait forever.
			if Time.get_ticks_msec() - _send_started_ms > CONNECT_TIMEOUT_MS * 4:
				_cancel_send("%s never confirmed the transfer." % _send_peer.name)
			return

		var response: PackedByteArray = _send_stream.get_data(available)[1]
		var header: PPSyncProtocol.Header = PPSyncProtocol.parse_header(response)

		if header.valid and header.type == PPSyncProtocol.MessageType.ACK:
			_finish_send(true, "Sent to %s." % _send_peer.name)
		else:
			var reason: String = "%s rejected the transfer." % _send_peer.name
			if header.valid and header.type == PPSyncProtocol.MessageType.REFUSE:
				var body: Dictionary = PPSyncProtocol.parse_json(
					response.slice(
						PPSyncProtocol.HEADER_SIZE,
						PPSyncProtocol.HEADER_SIZE + header.length
					)
				)
				reason = String(body.get("reason", reason))
			_finish_send(false, reason)


func _cancel_send(reason: String) -> void:
	if _send_state == SendState.IDLE:
		return
	_finish_send(false, reason)


func _finish_send(success: bool, message: String) -> void:
	var peer: PPSyncPeer = _send_peer

	if _send_stream != null:
		_send_stream.disconnect_from_host()
	_send_stream = null
	_send_bytes = PackedByteArray()
	_send_offset = 0
	_send_peer = null
	_send_state = SendState.IDLE

	if peer != null:
		transfer_finished.emit(peer, success, message)
