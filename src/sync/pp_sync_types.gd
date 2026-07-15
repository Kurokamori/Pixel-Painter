class_name PPSyncPeer
extends RefCounted

## A device we can send artwork to.

const STALE_AFTER_MS: int = 6000

var id: String = ""
var name: String = "Device"
var platform: String = "unknown"

## Transport-specific address. For LAN this is an IP; for Bluetooth it is the
## native plugin's device handle.
var address: String = ""
var port: int = 0

## Which transport found this peer -- "lan" or "bluetooth".
var transport: StringName = &"lan"

var last_seen_ms: int = 0


static func create(
	peer_id: String, peer_name: String, peer_platform: String, transport_id: StringName
) -> PPSyncPeer:
	var peer: PPSyncPeer = PPSyncPeer.new()
	peer.id = peer_id
	peer.name = peer_name
	peer.platform = peer_platform
	peer.transport = transport_id
	peer.last_seen_ms = Time.get_ticks_msec()
	return peer


func touch() -> void:
	last_seen_ms = Time.get_ticks_msec()


## A peer that has stopped beaconing is assumed gone. Six seconds is long enough
## to ride out a couple of dropped UDP beacons but short enough that a device
## that walked out of range disappears from the list promptly.
func is_stale() -> bool:
	return Time.get_ticks_msec() - last_seen_ms > STALE_AFTER_MS


## A stable key for deduplicating the same device seen over two transports.
func get_key() -> String:
	return "%s:%s" % [transport, id]
