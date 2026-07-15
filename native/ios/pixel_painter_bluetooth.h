// Godot-facing singleton for the iOS Bluetooth plugin.
//
// This header is pure C++ (no Objective-C), so it can be included from Godot's
// registration code. The CoreBluetooth machinery lives behind an opaque pointer
// in the .mm.

#pragma once

#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/variant/variant.h"

class PixelPainterBluetooth : public Object {
	GDCLASS(PixelPainterBluetooth, Object);

	static PixelPainterBluetooth *singleton;

	// Retained CoreBluetooth controller (PPBluetoothController *). Held as void*
	// so this header stays includable from plain C++ translation units.
	void *controller = nullptr;

protected:
	static void _bind_methods();

public:
	static PixelPainterBluetooth *get_singleton();

	void start(const String &p_device_id, const String &p_device_name, const String &p_platform);
	void stop();
	int send(const String &p_peer_handle, const PackedByteArray &p_bytes);

	// Called from the Objective-C delegates. These marshal onto the main thread
	// before emitting: CoreBluetooth calls back on its own dispatch queue, and
	// Godot signals must not cross a thread boundary unannounced.
	void on_peer_discovered(const String &p_handle, const String &p_id, const String &p_name, const String &p_platform);
	void on_peer_lost(const String &p_id);
	void on_data_received(const String &p_id, const PackedByteArray &p_bytes);
	void on_transfer_progress(const String &p_id, int p_sent, int p_total);
	void on_transfer_complete(const String &p_id, bool p_success, const String &p_message);

	PixelPainterBluetooth();
	~PixelPainterBluetooth();
};
