@abstract
class_name PPTransport
extends RefCounted

## What a sync transport has to provide.
##
## Two implementations exist: PPLanTransport (UDP discovery + TCP transfer) and
## PPBluetoothTransport (a bridge to a native plugin). The service layer above
## treats them identically, so a project can be sent over whichever transport
## happens to have found the device -- and a new transport (USB, cloud) is a new
## subclass and nothing else.

signal peer_found(peer: PPSyncPeer)
signal peer_lost(peer: PPSyncPeer)
signal transfer_started(peer: PPSyncPeer, total_bytes: int)
signal transfer_progress(peer: PPSyncPeer, sent_bytes: int, total_bytes: int)
signal transfer_finished(peer: PPSyncPeer, success: bool, message: String)
signal project_received(from: PPSyncPeer, bytes: PackedByteArray)
signal availability_changed()


@abstract func get_id() -> StringName

@abstract func get_display_name() -> String


## Whether this transport can run at all on this device right now. Bluetooth
## returns false when the native plugin is absent, and `get_unavailable_reason()`
## explains why -- the UI shows that instead of a dead button.
@abstract func is_available() -> bool


func get_unavailable_reason() -> String:
	return ""


## A transport that is working but degraded says so here. Distinct from being
## unavailable: the transport still functions, the user just deserves to know it
## is not at full strength.
func get_warning() -> String:
	return ""


@abstract func start() -> Error

@abstract func stop() -> void


## Called every frame by PPSyncService. Transports are polled rather than
## threaded so that every signal lands on the main thread and the UI never has
## to think about locking.
@abstract func poll() -> void


@abstract func get_peers() -> Array[PPSyncPeer]


## Begins sending `bytes` (an encoded .pxp) to `peer`. Progress and completion
## arrive as signals; this returns immediately.
@abstract func send_project(peer: PPSyncPeer, bytes: PackedByteArray, project_name: String) -> Error


func is_busy() -> bool:
	return false
