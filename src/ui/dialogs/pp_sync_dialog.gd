class_name PPSyncDialog
extends AcceptDialog

## Device discovery and one-tap send.
##
## Every transport's availability is shown explicitly, including *why* it is
## unavailable. Bluetooth in particular needs a native plugin that is not in
## every build, and a greyed-out button with no explanation is the most
## infuriating possible way to communicate that.

signal send_requested(peer: PPSyncPeer)

var _sync: PPSyncService = null
var _prefs: PPSettings = null

@onready var _device_name: LineEdit = %DeviceNameEdit
@onready var _transport_status: VBoxContainer = %TransportStatus
@onready var _peers: VBoxContainer = %Peers
@onready var _empty: Label = %EmptyLabel
@onready var _progress: VBoxContainer = %Progress
@onready var _progress_label: Label = %ProgressLabel
@onready var _progress_bar: ProgressBar = %ProgressBar


func bind(service: PPSyncService) -> void:
	_sync = service
	_prefs = PPSettings.get_instance()

	_device_name.text = _prefs.device_name
	_device_name.text_submitted.connect(_on_name_submitted)
	_device_name.focus_exited.connect(
		func() -> void: _on_name_submitted(_device_name.text)
	)

	_sync.peers_changed.connect(_refresh_peers)
	_sync.availability_changed.connect(_refresh_transports)
	_sync.transfer_started.connect(_on_transfer_started)
	_sync.transfer_progress.connect(_on_transfer_progress)
	_sync.transfer_finished.connect(_on_transfer_finished)

	_refresh_transports()
	_refresh_peers()


func open() -> void:
	_refresh_transports()
	_refresh_peers()
	popup_centered()


func _on_name_submitted(text: String) -> void:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty() or trimmed == _prefs.device_name:
		return
	_prefs.device_name = trimmed
	_prefs.save_settings()


func _refresh_transports() -> void:
	for child: Node in _transport_status.get_children():
		child.queue_free()

	for transport: PPTransport in _sync.get_transports():
		var label: Label = Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		if transport.is_available():
			var warning: String = transport.get_warning()
			if warning.is_empty():
				label.text = "✓  %s — ready" % transport.get_display_name()
				label.add_theme_color_override("font_color", Color(0.44, 0.83, 0.51))
			else:
				label.text = "!  %s — %s" % [transport.get_display_name(), warning]
				label.add_theme_color_override("font_color", Color(0.9, 0.78, 0.4))
		else:
			label.text = "✕  %s — %s" % [
				transport.get_display_name(), transport.get_unavailable_reason()
			]
			label.add_theme_color_override("font_color", Color(0.85, 0.65, 0.35))

		_transport_status.add_child(label)


func _refresh_peers() -> void:
	for child: Node in _peers.get_children():
		if child != _empty:
			child.queue_free()

	var peers: Array[PPSyncPeer] = _sync.get_peers()
	_empty.visible = peers.is_empty()

	for peer: PPSyncPeer in peers:
		_peers.add_child(_build_peer_row(peer))


func _build_peer_row(peer: PPSyncPeer) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label: Label = Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "%s  ·  %s over %s" % [
		peer.name, peer.platform, _sync.get_transport(peer.transport).get_display_name()
	]
	row.add_child(label)

	var send: Button = Button.new()
	send.text = "Send"
	send.custom_minimum_size = Vector2(90, 40)
	send.disabled = _sync.is_busy()
	send.pressed.connect(func() -> void: send_requested.emit(peer))
	row.add_child(send)

	return row


func _on_transfer_started(peer: PPSyncPeer, total_bytes: int) -> void:
	_progress.visible = true
	_progress_bar.value = 0.0
	_progress_label.text = "Sending to %s — %s" % [
		peer.name, String.humanize_size(total_bytes)
	]
	_refresh_peers()


func _on_transfer_progress(_peer: PPSyncPeer, sent: int, total: int) -> void:
	if total <= 0:
		return
	_progress_bar.value = float(sent) / float(total)


func _on_transfer_finished(_peer: PPSyncPeer, success: bool, message: String) -> void:
	_progress_bar.value = 1.0 if success else 0.0
	_progress_label.text = message
	_refresh_peers()

	# Leave the outcome on screen briefly rather than snapping the bar away, so
	# a fast transfer does not look like nothing happened.
	await get_tree().create_timer(2.5).timeout
	if is_instance_valid(self):
		_progress.visible = false
