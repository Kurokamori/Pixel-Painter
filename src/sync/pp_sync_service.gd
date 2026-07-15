class_name PPSyncService
extends Node

## The app's single view of "who can I send this to, and how".
##
## Owns every transport, merges their peer lists, and routes a send to whichever
## transport found the chosen peer. The UI talks only to this.
##
## Lives as a node in app_root.tscn rather than as an autoload, so that every
## reference to it is statically type-checked.

signal peers_changed()
signal transfer_started(peer: PPSyncPeer, total_bytes: int)
signal transfer_progress(peer: PPSyncPeer, sent_bytes: int, total_bytes: int)
signal transfer_finished(peer: PPSyncPeer, success: bool, message: String)

## An incoming project. The app decides whether to open it (auto-accept, or a
## prompt), which is why this carries bytes rather than a document.
signal project_offered(from: PPSyncPeer, bytes: PackedByteArray, project_name: String)

signal availability_changed()

var _transports: Array[PPTransport] = []
var _running: bool = false


func _ready() -> void:
	_transports = [PPLanTransport.new(), PPBluetoothTransport.new()]

	for transport: PPTransport in _transports:
		transport.peer_found.connect(_on_peer_found)
		transport.peer_lost.connect(_on_peer_lost)
		transport.transfer_started.connect(_on_transfer_started)
		transport.transfer_progress.connect(_on_transfer_progress)
		transport.transfer_finished.connect(_on_transfer_finished)
		transport.project_received.connect(_on_project_received)
		transport.availability_changed.connect(_on_availability_changed)

	if PPSettings.get_instance().sync_enabled:
		start()


func _process(_delta: float) -> void:
	if not _running:
		return
	for transport: PPTransport in _transports:
		if transport.is_available():
			transport.poll()


func start() -> void:
	if _running:
		return
	_running = true
	for transport: PPTransport in _transports:
		if transport.is_available():
			transport.start()
	availability_changed.emit()


func stop() -> void:
	if not _running:
		return
	_running = false
	for transport: PPTransport in _transports:
		transport.stop()
	peers_changed.emit()


func is_running() -> bool:
	return _running


func get_transports() -> Array[PPTransport]:
	return _transports


func get_transport(id: StringName) -> PPTransport:
	for transport: PPTransport in _transports:
		if transport.get_id() == id:
			return transport
	return null


## Every peer across every transport. A device reachable over both LAN and
## Bluetooth appears once per transport, because the two are genuinely different
## routes with different speed and reliability -- and the user may care which.
func get_peers() -> Array[PPSyncPeer]:
	var peers: Array[PPSyncPeer] = []
	for transport: PPTransport in _transports:
		if not transport.is_available():
			continue
		peers.append_array(transport.get_peers())
	return peers


func is_busy() -> bool:
	for transport: PPTransport in _transports:
		if transport.is_busy():
			return true
	return false


## Encodes `document` and sends it to `peer` over the transport that found it.
func send_document(peer: PPSyncPeer, document: PPDocument) -> Error:
	var transport: PPTransport = get_transport(peer.transport)
	if transport == null or not transport.is_available():
		return ERR_UNAVAILABLE

	var bytes: PackedByteArray = PPProjectIO.encode(document)
	if bytes.is_empty():
		return ERR_CANT_CREATE

	return transport.send_project(peer, bytes, document.get_title())


func _on_peer_found(_peer: PPSyncPeer) -> void:
	peers_changed.emit()


func _on_peer_lost(_peer: PPSyncPeer) -> void:
	peers_changed.emit()


func _on_transfer_started(peer: PPSyncPeer, total_bytes: int) -> void:
	transfer_started.emit(peer, total_bytes)


func _on_transfer_progress(peer: PPSyncPeer, sent: int, total: int) -> void:
	transfer_progress.emit(peer, sent, total)


func _on_transfer_finished(peer: PPSyncPeer, success: bool, message: String) -> void:
	transfer_finished.emit(peer, success, message)


func _on_project_received(from: PPSyncPeer, bytes: PackedByteArray) -> void:
	# Peek at the manifest for a name to show in the prompt, without committing
	# to fully decoding a project the user may well decline.
	project_offered.emit(from, bytes, _peek_name(bytes))


func _on_availability_changed() -> void:
	availability_changed.emit()


func _peek_name(bytes: PackedByteArray) -> String:
	var document: PPDocument = PPProjectIO.decode(bytes)
	if document == null:
		return "Untitled"
	return "%d x %d, %d frame(s)" % [
		document.sprite.size.x,
		document.sprite.size.y,
		document.sprite.frame_count(),
	]
