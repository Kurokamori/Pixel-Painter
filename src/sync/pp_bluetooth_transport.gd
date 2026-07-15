class_name PPBluetoothTransport
extends PPTransport

## Sync over Bluetooth LE.
##
## Godot 4.7 exposes no Bluetooth API of any kind (there is no BluetoothAdvertiser
## / BluetoothEnumerator class in the engine), so this cannot be done in GDScript.
## Bluetooth therefore lives behind a *native singleton*:
##
##   iOS      native/ios/     CoreBluetooth, using an L2CAP channel for bulk
##                            transfer (GATT characteristic writes cap out around
##                            512 bytes and would be hopeless for a megabyte
##                            project).
##   Windows  native/windows/ A GDExtension over WinRT's Bluetooth LE APIs.
##
## Both must be compiled on their own platform's toolchain -- Xcode for iOS,
## MSVC for Windows -- and dropped into the project before Bluetooth appears.
## See native/README.md for the build steps.
##
## When the singleton is absent this transport reports itself unavailable with a
## reason, and the UI shows that reason. It never silently pretends to work: a
## sync feature that quietly does nothing is worse than one that says it is off.

const SINGLETON_NAME: String = "PixelPainterBluetooth"

var _native: Object = null
var _peers: Dictionary[String, PPSyncPeer] = {}
var _running: bool = false
var _busy: bool = false


func get_id() -> StringName:
	return &"bluetooth"


func get_display_name() -> String:
	return "Bluetooth"


func is_available() -> bool:
	return _resolve_native() != null


func get_unavailable_reason() -> String:
	if _resolve_native() != null:
		return ""

	match OS.get_name():
		"iOS":
			return (
				"The Bluetooth plugin is not present in this build. "
				+ "Build native/ios with Xcode and re-export."
			)
		"Windows":
			return (
				"The Bluetooth GDExtension is not present in this build. "
				+ "Build native/windows with MSVC and re-export."
			)
	return "Bluetooth is not supported on %s. Use Wi-Fi / LAN instead." % OS.get_name()


func _resolve_native() -> Object:
	if _native != null:
		return _native
	if not Engine.has_singleton(SINGLETON_NAME):
		return null
	_native = Engine.get_singleton(SINGLETON_NAME)
	return _native


func start() -> Error:
	if _running:
		return OK

	var native: Object = _resolve_native()
	if native == null:
		return ERR_UNAVAILABLE

	# The native side speaks in plain ids and byte arrays; everything is adapted
	# into PPSyncPeer here so the rest of the app never sees the difference
	# between a Bluetooth peer and a LAN one.
	native.connect("peer_discovered", _on_peer_discovered)
	native.connect("peer_lost", _on_peer_lost)
	native.connect("data_received", _on_data_received)
	native.connect("transfer_progress", _on_transfer_progress)
	native.connect("transfer_complete", _on_transfer_complete)

	var settings: PPSettings = PPSettings.get_instance()
	native.call("start", settings.device_id, settings.device_name, OS.get_name())

	_running = true
	availability_changed.emit()
	return OK


func stop() -> void:
	if not _running:
		return
	_running = false

	var native: Object = _resolve_native()
	if native != null:
		native.call("stop")
		native.disconnect("peer_discovered", _on_peer_discovered)
		native.disconnect("peer_lost", _on_peer_lost)
		native.disconnect("data_received", _on_data_received)
		native.disconnect("transfer_progress", _on_transfer_progress)
		native.disconnect("transfer_complete", _on_transfer_complete)

	for peer: PPSyncPeer in _peers.values():
		peer_lost.emit(peer)
	_peers.clear()


func poll() -> void:
	if not _running:
		return
	var native: Object = _resolve_native()
	if native == null:
		return

	# The iOS plugin runs CoreBluetooth on the main queue and emits directly, so
	# it has nothing to drain. The Windows GDExtension cannot: WinRT completes its
	# async work on threadpool threads, and emitting a Godot signal from one would
	# race the scene tree. It therefore queues events and exposes poll_events() to
	# drain them here, on the main thread.
	if native.has_method("poll_events"):
		native.call("poll_events")


func get_peers() -> Array[PPSyncPeer]:
	var list: Array[PPSyncPeer] = []
	for peer: PPSyncPeer in _peers.values():
		list.append(peer)
	list.sort_custom(func(a: PPSyncPeer, b: PPSyncPeer) -> bool: return a.name < b.name)
	return list


func is_busy() -> bool:
	return _busy


func send_project(
	peer: PPSyncPeer, bytes: PackedByteArray, project_name: String
) -> Error:
	var native: Object = _resolve_native()
	if native == null:
		return ERR_UNAVAILABLE
	if _busy:
		return ERR_BUSY

	var settings: PPSettings = PPSettings.get_instance()
	var envelope: PackedByteArray = PPSyncProtocol.frame_json(
		PPSyncProtocol.MessageType.HELLO,
		{
			"id": settings.device_id,
			"name": settings.device_name,
			"platform": OS.get_name(),
			"project": project_name,
		}
	)
	envelope.append_array(
		PPSyncProtocol.frame(PPSyncProtocol.MessageType.PROJECT, bytes)
	)

	_busy = true
	transfer_started.emit(peer, envelope.size())

	var error: int = native.call("send", peer.address, envelope)
	if error != OK:
		_busy = false
		transfer_finished.emit(peer, false, "Bluetooth send failed.")
		return error as Error

	return OK


# --- Native callbacks -------------------------------------------------------

func _on_peer_discovered(
	handle: String, id: String, name: String, platform: String
) -> void:
	var key: String = "bt:%s" % id
	if _peers.has(key):
		_peers[key].touch()
		_peers[key].address = handle
		return

	var peer: PPSyncPeer = PPSyncPeer.create(id, name, platform, &"bluetooth")
	peer.address = handle
	_peers[key] = peer
	peer_found.emit(peer)


func _on_peer_lost(id: String) -> void:
	var key: String = "bt:%s" % id
	if not _peers.has(key):
		return
	var peer: PPSyncPeer = _peers[key]
	_peers.erase(key)
	peer_lost.emit(peer)


func _on_data_received(id: String, bytes: PackedByteArray) -> void:
	# The native layer reassembles the stream and hands us whole envelopes.
	var offset: int = 0
	var from: PPSyncPeer = _peers.get("bt:%s" % id, null)
	if from == null:
		from = PPSyncPeer.create(id, "Bluetooth Device", "unknown", &"bluetooth")

	while offset + PPSyncProtocol.HEADER_SIZE <= bytes.size():
		var header: PPSyncProtocol.Header = PPSyncProtocol.parse_header(
			bytes.slice(offset)
		)
		if not header.valid:
			return

		var start: int = offset + PPSyncProtocol.HEADER_SIZE
		var end: int = start + header.length
		if end > bytes.size():
			return

		var payload: PackedByteArray = bytes.slice(start, end)
		offset = end

		match header.type:
			PPSyncProtocol.MessageType.HELLO:
				var data: Dictionary = PPSyncProtocol.parse_json(payload)
				from.name = String(data.get("name", from.name))
				from.platform = String(data.get("platform", from.platform))
			PPSyncProtocol.MessageType.PROJECT:
				# Bluetooth has no end-to-end integrity guarantee the way TCP
				# does, so the CRC in our own header is the only thing standing
				# between a flipped bit and a corrupt project.
				if not PPSyncProtocol.verify(header, payload):
					return
				project_received.emit(from, payload)


func _on_transfer_progress(id: String, sent: int, total: int) -> void:
	var peer: PPSyncPeer = _peers.get("bt:%s" % id, null)
	if peer == null:
		return
	transfer_progress.emit(peer, sent, total)


func _on_transfer_complete(id: String, success: bool, message: String) -> void:
	_busy = false
	var peer: PPSyncPeer = _peers.get("bt:%s" % id, null)
	if peer == null:
		return
	transfer_finished.emit(peer, success, message)
