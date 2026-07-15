class_name PPTestSync
extends RefCounted

## Covers the wire format and the transport contract.
##
## The LAN transport's actual socket traffic is exercised by the manual
## round-trip in tools/sync_loopback.gd (two processes on one machine); what is
## unit-testable here is the framing, which is where silent corruption would
## come from.


static func run() -> PPTestCase:
	var t: PPTestCase = PPTestCase.new("sync")

	_test_framing(t)
	_test_crc(t)
	_test_rejects_garbage(t)
	_test_peer_staleness(t)
	_test_transport_availability(t)

	return t


static func _test_framing(t: PPTestCase) -> void:
	var payload: PackedByteArray = PackedByteArray()
	for i: int in range(1000):
		payload.append(i % 256)

	var framed: PackedByteArray = PPSyncProtocol.frame(
		PPSyncProtocol.MessageType.PROJECT, payload
	)
	t.equal(
		framed.size(),
		PPSyncProtocol.HEADER_SIZE + payload.size(),
		"a frame is its header plus its payload"
	)

	var header: PPSyncProtocol.Header = PPSyncProtocol.parse_header(framed)
	t.check(header.valid, "a framed message parses")
	t.equal(header.type, PPSyncProtocol.MessageType.PROJECT, "message type survives")
	t.equal(header.length, payload.size(), "payload length survives")

	var body: PackedByteArray = framed.slice(
		PPSyncProtocol.HEADER_SIZE, PPSyncProtocol.HEADER_SIZE + header.length
	)
	t.check(body == payload, "payload bytes survive")
	t.check(PPSyncProtocol.verify(header, body), "checksum validates the payload")

	var json_frame: PackedByteArray = PPSyncProtocol.frame_json(
		PPSyncProtocol.MessageType.HELLO, {"id": "abc", "name": "iPad"}
	)
	var json_header: PPSyncProtocol.Header = PPSyncProtocol.parse_header(json_frame)
	t.check(json_header.valid, "a json frame parses")
	var decoded: Dictionary = PPSyncProtocol.parse_json(
		json_frame.slice(
			PPSyncProtocol.HEADER_SIZE,
			PPSyncProtocol.HEADER_SIZE + json_header.length
		)
	)
	t.equal(String(decoded.get("name", "")), "iPad", "json payload round-trips")


static func _test_crc(t: PPTestCase) -> void:
	# The standard CRC-32 of "123456789" is 0xCBF43926 -- the canonical check
	# value, and the fastest way to prove the table and the polynomial are right.
	var check: PackedByteArray = "123456789".to_ascii_buffer()
	t.equal(PPSyncProtocol._crc32(check), 0xCBF43926, "CRC-32 matches the standard check value")

	var payload: PackedByteArray = PackedByteArray([1, 2, 3, 4, 5])
	var framed: PackedByteArray = PPSyncProtocol.frame(
		PPSyncProtocol.MessageType.PROJECT, payload
	)
	var header: PPSyncProtocol.Header = PPSyncProtocol.parse_header(framed)

	var corrupted: PackedByteArray = payload.duplicate()
	corrupted[2] = 99
	t.check(
		not PPSyncProtocol.verify(header, corrupted),
		"a single flipped byte fails the checksum"
	)


static func _test_rejects_garbage(t: PPTestCase) -> void:
	t.check(
		not PPSyncProtocol.parse_header(PackedByteArray([1, 2, 3])).valid,
		"a short buffer is not a valid header"
	)
	t.check(
		not PPSyncProtocol.parse_header(PackedByteArray()).valid,
		"an empty buffer is not a valid header"
	)

	# A plausible-looking header with a hostile length must be refused outright
	# rather than believed and allocated.
	var hostile: StreamPeerBuffer = StreamPeerBuffer.new()
	hostile.big_endian = false
	hostile.put_u32(PPSyncProtocol.MAGIC)
	hostile.put_u16(PPSyncProtocol.VERSION)
	hostile.put_u16(int(PPSyncProtocol.MessageType.PROJECT))
	hostile.put_u32(PPSyncProtocol.MAX_PAYLOAD + 1)
	hostile.put_u32(0)
	t.check(
		not PPSyncProtocol.parse_header(hostile.data_array).valid,
		"an absurd payload length is rejected"
	)

	var wrong_magic: StreamPeerBuffer = StreamPeerBuffer.new()
	wrong_magic.big_endian = false
	wrong_magic.put_u32(0xDEADBEEF)
	wrong_magic.put_u16(PPSyncProtocol.VERSION)
	wrong_magic.put_u16(0)
	wrong_magic.put_u32(0)
	wrong_magic.put_u32(0)
	t.check(
		not PPSyncProtocol.parse_header(wrong_magic.data_array).valid,
		"a foreign protocol is rejected"
	)


static func _test_peer_staleness(t: PPTestCase) -> void:
	var peer: PPSyncPeer = PPSyncPeer.create("id-1", "Studio PC", "Windows", &"lan")
	t.check(not peer.is_stale(), "a freshly seen peer is not stale")
	t.equal(peer.get_key(), "lan:id-1", "peer key namespaces by transport")

	# Backdate the last sighting past the staleness window.
	peer.last_seen_ms = Time.get_ticks_msec() - (PPSyncPeer.STALE_AFTER_MS + 100)
	t.check(peer.is_stale(), "a peer that stopped beaconing goes stale")

	peer.touch()
	t.check(not peer.is_stale(), "touching a peer revives it")


static func _test_transport_availability(t: PPTestCase) -> void:
	var lan: PPLanTransport = PPLanTransport.new()
	t.equal(lan.get_id(), &"lan", "lan transport id")
	t.check(lan.is_available(), "lan transport is available before it has failed")

	var bluetooth: PPBluetoothTransport = PPBluetoothTransport.new()
	t.equal(bluetooth.get_id(), &"bluetooth", "bluetooth transport id")

	# The native plugin is not compiled into the headless test binary, so this
	# must report unavailable *and say why* rather than pretending to work.
	t.check(
		not bluetooth.is_available(),
		"bluetooth is unavailable without its native plugin"
	)
	t.check(
		not bluetooth.get_unavailable_reason().is_empty(),
		"an unavailable transport explains itself"
	)
	t.equal(
		bluetooth.send_project(
			PPSyncPeer.create("x", "x", "x", &"bluetooth"), PackedByteArray([1]), "test"
		),
		ERR_UNAVAILABLE,
		"sending over an unavailable transport fails cleanly"
	)
