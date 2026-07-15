// Windows Bluetooth LE transport, exposed to Godot as the PixelPainterBluetooth
// singleton (the same contract the iOS plugin implements).

#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <vector>

namespace godot {

class BluetoothBackend;

class PixelPainterBluetooth : public Object {
	GDCLASS(PixelPainterBluetooth, Object)

protected:
	static void _bind_methods();

public:
	void start(const String &p_device_id, const String &p_device_name, const String &p_platform);
	void stop();
	int send(const String &p_peer_handle, const PackedByteArray &p_bytes);

	// WinRT completes its async work on threadpool threads. Godot signals must be
	// emitted on the main thread, so the backend queues events here and this
	// drains them from _process on the scene tree.
	void poll_events();

	// Called by the backend from arbitrary threads.
	void queue_peer_discovered(const String &p_handle, const String &p_id, const String &p_name,
			const String &p_platform);
	void queue_peer_lost(const String &p_id);
	void queue_data_received(const String &p_id, const PackedByteArray &p_bytes);
	void queue_transfer_progress(const String &p_id, int64_t p_sent, int64_t p_total);
	void queue_transfer_complete(const String &p_id, bool p_success, const String &p_message);

	PixelPainterBluetooth();
	~PixelPainterBluetooth();

private:
	enum class EventType {
		PEER_DISCOVERED,
		PEER_LOST,
		DATA_RECEIVED,
		TRANSFER_PROGRESS,
		TRANSFER_COMPLETE,
	};

	struct Event {
		EventType type;
		String handle;
		String id;
		String name;
		String platform;
		String message;
		PackedByteArray bytes;
		int64_t sent = 0;
		int64_t total = 0;
		bool success = false;
	};

	std::unique_ptr<BluetoothBackend> backend;
	std::mutex event_mutex;
	std::vector<Event> pending;

	void push_event(Event &&p_event);
};

} // namespace godot
