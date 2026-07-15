extends SceneTree

## End-to-end LAN sync check across two real processes.
##
##   Terminal A:  godot --headless --path . --script tools/sync_loopback.gd -- send
##   Terminal B:  godot --headless --path . --script tools/sync_loopback.gd -- receive
##
## Start order matters, and for a reason worth knowing: only one process on a
## machine can bind the UDP discovery port, so only the *first* one started can
## discover peers. The sender must therefore go first. The receiver still beacons
## from its own separate socket (see PPLanTransport) and still listens on TCP, so
## the sender finds it and can send to it -- which is exactly the degradation the
## split-socket design was built to survive.
##
## On two real devices this ordering does not matter; both bind the port fine.
##
## This exercises the whole chain that unit tests cannot: UDP beacon emission and
## parsing, peer discovery, TCP connect, framing, chunked transfer, CRC
## verification, ACK, and project decode. Prints RESULT: PASS or RESULT: FAIL.

const TIMEOUT_SECONDS: float = 25.0

var _transport: PPLanTransport = null
var _mode: String = "receive"
var _done: bool = false
var _sent: bool = false
var _elapsed: float = 0.0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_mode = args[0]

	# Each process needs a distinct identity, or they will filter each other's
	# beacons out as their own echo.
	var prefs: PPSettings = PPSettings.get_instance()
	prefs.device_id = "loopback-%s-%d" % [_mode, OS.get_process_id()]
	prefs.device_name = "Loopback %s" % _mode.capitalize()

	_transport = PPLanTransport.new()
	_transport.peer_found.connect(_on_peer_found)
	_transport.project_received.connect(_on_project_received)
	_transport.transfer_finished.connect(_on_transfer_finished)

	var error: Error = _transport.start()
	if error != OK:
		print("RESULT: FAIL — transport could not start (error %d)" % error)
		quit(1)
		return

	print("[%s] listening; id=%s" % [_mode, prefs.device_id])
	if not _transport.get_warning().is_empty():
		print("[%s] warning: %s" % [_mode, _transport.get_warning()])


func _process(delta: float) -> bool:
	if _done:
		return true

	_transport.poll()

	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		print("RESULT: FAIL — timed out after %.0fs in '%s' mode" % [TIMEOUT_SECONDS, _mode])
		_transport.stop()
		quit(1)
		return true

	return false


func _on_peer_found(peer: PPSyncPeer) -> void:
	print("[%s] discovered %s at %s:%d" % [_mode, peer.name, peer.address, peer.port])

	if _mode != "send" or _sent:
		return
	# Only send to the loopback receiver, not to some other Pixel Painter that
	# happens to be running on the network.
	if not peer.name.to_lower().contains("receive"):
		return

	_sent = true
	var document: PPDocument = _build_document()
	var bytes: PackedByteArray = PPProjectIO.encode(document)
	print("[send] sending %d bytes to %s" % [bytes.size(), peer.name])

	var error: Error = _transport.send_project(peer, bytes, "loopback")
	if error != OK:
		print("RESULT: FAIL — send_project returned %d" % error)
		_finish(1)


func _on_transfer_finished(_peer: PPSyncPeer, success: bool, message: String) -> void:
	if _mode != "send":
		return
	if not success:
		print("RESULT: FAIL — %s" % message)
		_finish(1)
		return
	print("RESULT: PASS — %s" % message)
	_finish(0)


func _on_project_received(from: PPSyncPeer, bytes: PackedByteArray) -> void:
	if _mode != "receive":
		return

	print("[receive] got %d bytes from %s" % [bytes.size(), from.name])

	var document: PPDocument = PPProjectIO.decode(bytes)
	if document == null:
		print("RESULT: FAIL — the received bytes did not decode")
		_finish(1)
		return

	# Verify the artwork survived the wire, not merely that bytes arrived.
	var sprite: PPSprite = document.sprite
	var checks: Array[bool] = [
		sprite.size == Vector2i(24, 16),
		sprite.layer_count() == 2,
		sprite.frame_count() == 3,
		sprite.get_layer(1).blend_mode == PPTypes.BlendMode.MULTIPLY,
		sprite.get_cel(0, 0).image.get_pixel(3, 3).is_equal_approx(Color(1.0, 0.0, 0.0, 1.0)),
		sprite.get_cel(0, 1) == sprite.get_cel(0, 2),
		sprite.tags.size() == 1,
	]

	for i: int in range(checks.size()):
		if not checks[i]:
			print("RESULT: FAIL — received project failed integrity check %d" % i)
			_finish(1)
			return

	print("RESULT: PASS — %d x %d, %d layers, %d frames, linked cel intact" % [
		sprite.size.x, sprite.size.y, sprite.layer_count(), sprite.frame_count()
	])
	_finish(0)


## Deliberately not a trivial sprite: multiple layers, a non-default blend mode,
## a linked cel and a tag, so a lossy transfer shows up as a failed check rather
## than a passing byte count.
func _build_document() -> PPDocument:
	var document: PPDocument = PPDocument.create(
		Vector2i(24, 16), PPDefaultPalettes.get_palette("PICO-8")
	)
	var sprite: PPSprite = document.sprite

	sprite.get_cel(0, 0).image.fill_rect(Rect2i(2, 2, 6, 6), Color(1.0, 0.0, 0.0, 1.0))

	var top: PPLayer = PPLayer.create("Shade", 1, sprite.size)
	top.blend_mode = PPTypes.BlendMode.MULTIPLY
	sprite.add_layer(top, 1)

	sprite.insert_frame(1)
	sprite.insert_frame(2)
	sprite.get_layer(0).cels[2] = sprite.get_layer(0).cels[1]

	sprite.tags.append(PPTag.create("walk", 0, 2))
	return document


func _finish(code: int) -> void:
	_done = true
	_transport.stop()
	quit(code)
