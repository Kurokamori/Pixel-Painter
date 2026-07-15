// Windows Bluetooth LE, via C++/WinRT.
//
// The device runs both roles, as on iOS:
//
//   Central     watches for advertisements carrying our service UUID, connects,
//               reads the peer's identity, and writes chunked payload bytes.
//   Peripheral  publishes the service via GattServiceProvider and accepts writes.
//
// WinRT gives us no BLE L2CAP channel (unlike CoreBluetooth), so Windows always
// uses the chunked-GATT path. That caps throughput at roughly 20-100 KB/s. See
// native/README.md -- this is a platform limit, not a shortcut.

#include "pixel_painter_bluetooth.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <cstring>
#include <string>

#include "../../shared/pp_bluetooth_uuids.h"

using namespace winrt;
using namespace winrt::Windows::Devices::Bluetooth;
using namespace winrt::Windows::Devices::Bluetooth::Advertisement;
using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Storage::Streams;

namespace godot {

static guid parse_guid(const char *p_text) {
	// winrt::guid has no constructor from a plain char*, so route through the
	// wide-string form the API does accept.
	std::string narrow(p_text);
	std::wstring wide(narrow.begin(), narrow.end());
	return guid(L"{" + wide + L"}");
}

// --- Backend ----------------------------------------------------------------

class BluetoothBackend {
public:
	explicit BluetoothBackend(PixelPainterBluetooth *p_owner) :
			owner(p_owner) {}

	void start(const std::string &p_id, const std::string &p_name, const std::string &p_platform);
	void stop();
	int send(const std::string &p_handle, const std::vector<uint8_t> &p_bytes);

private:
	struct Peer {
		BluetoothLEDevice device{ nullptr };
		GattCharacteristic tx{ nullptr };
		std::string id;
		std::string name;
		std::string platform;

		std::vector<uint8_t> outbound;
		size_t outbound_offset = 0;
		uint16_t mtu = PP_BT_DEFAULT_CHUNK;
	};

	struct Inbound {
		std::vector<uint8_t> buffer;
		uint32_t expected = 0;
	};

	PixelPainterBluetooth *owner = nullptr;
	bool running = false;

	std::string device_id;
	std::string device_name;
	std::string device_platform;

	BluetoothLEAdvertisementWatcher watcher{ nullptr };
	GattServiceProvider provider{ nullptr };
	GattLocalCharacteristic tx_characteristic{ nullptr };

	std::mutex peers_mutex;
	std::map<std::string, std::shared_ptr<Peer>> peers;
	std::map<std::string, Inbound> inbound;

	fire_and_forget begin_advertising();
	fire_and_forget on_advertisement(const BluetoothLEAdvertisementReceivedEventArgs &args);
	fire_and_forget connect_peer(uint64_t address);
	fire_and_forget pump(std::shared_ptr<Peer> peer);

	void ingest(const std::string &key, const uint8_t *data, size_t length);
	void finish(const std::shared_ptr<Peer> &peer, bool success, const std::string &message);
};

void BluetoothBackend::start(const std::string &p_id, const std::string &p_name,
		const std::string &p_platform) {
	if (running) {
		return;
	}
	running = true;
	device_id = p_id;
	device_name = p_name;
	device_platform = p_platform;

	init_apartment(apartment_type::multi_threaded);

	watcher = BluetoothLEAdvertisementWatcher();
	watcher.ScanningMode(BluetoothLEScanningMode::Active);
	watcher.AdvertisementFilter().Advertisement().ServiceUuids().Append(
			parse_guid(PP_BT_SERVICE_UUID));
	watcher.Received([this](BluetoothLEAdvertisementWatcher const &,
								   BluetoothLEAdvertisementReceivedEventArgs const &args) {
		on_advertisement(args);
	});
	watcher.Start();

	begin_advertising();
}

fire_and_forget BluetoothBackend::begin_advertising() {
	auto result = co_await GattServiceProvider::CreateAsync(parse_guid(PP_BT_SERVICE_UUID));
	if (result.Error() != BluetoothError::Success) {
		// Unpackaged desktop apps are sometimes refused the peripheral role. That
		// is survivable: we can still act as a central and both send to, and be
		// discovered by, an advertising peer.
		co_return;
	}
	provider = result.ServiceProvider();

	GattLocalCharacteristicParameters tx_params;
	tx_params.CharacteristicProperties(GattCharacteristicProperties::Write |
			GattCharacteristicProperties::WriteWithoutResponse);
	tx_params.WriteProtectionLevel(GattProtectionLevel::Plain);

	auto tx_result = co_await provider.Service().CreateCharacteristicAsync(
			parse_guid(PP_BT_TX_CHAR_UUID), tx_params);
	if (tx_result.Error() != BluetoothError::Success) {
		co_return;
	}
	tx_characteristic = tx_result.Characteristic();

	tx_characteristic.WriteRequested([this](GattLocalCharacteristic const &,
											   GattWriteRequestedEventArgs const &args) -> fire_and_forget {
		auto deferral = args.GetDeferral();
		auto request = co_await args.GetRequestAsync();

		auto reader = DataReader::FromBuffer(request.Value());
		std::vector<uint8_t> chunk(reader.UnconsumedBufferLength());
		if (!chunk.empty()) {
			reader.ReadBytes(chunk);
		}

		std::string key = to_string(args.Session().DeviceId().Id());
		ingest(key, chunk.data(), chunk.size());

		if (request.Option() == GattWriteOption::WriteWithResponse) {
			request.Respond();
		}
		deferral.Complete();
	});

	// Identity, so the peer can name us without a round trip.
	GattLocalCharacteristicParameters identity_params;
	identity_params.CharacteristicProperties(GattCharacteristicProperties::Read);
	identity_params.ReadProtectionLevel(GattProtectionLevel::Plain);

	std::string identity = "{\"id\":\"" + device_id + "\",\"name\":\"" + device_name +
			"\",\"platform\":\"" + device_platform + "\"}";

	DataWriter identity_writer;
	identity_writer.WriteBytes(array_view<const uint8_t>(
			reinterpret_cast<const uint8_t *>(identity.data()),
			reinterpret_cast<const uint8_t *>(identity.data()) + identity.size()));
	identity_params.StaticValue(identity_writer.DetachBuffer());

	co_await provider.Service().CreateCharacteristicAsync(
			parse_guid(PP_BT_IDENTITY_CHAR_UUID), identity_params);

	// PSM of 0 tells iOS peers "no L2CAP here, use chunked GATT writes".
	GattLocalCharacteristicParameters psm_params;
	psm_params.CharacteristicProperties(GattCharacteristicProperties::Read);
	psm_params.ReadProtectionLevel(GattProtectionLevel::Plain);
	DataWriter psm_writer;
	psm_writer.WriteUInt16(0);
	psm_params.StaticValue(psm_writer.DetachBuffer());

	co_await provider.Service().CreateCharacteristicAsync(
			parse_guid(PP_BT_PSM_CHAR_UUID), psm_params);

	GattServiceProviderAdvertisingParameters advertising;
	advertising.IsConnectable(true);
	advertising.IsDiscoverable(true);
	provider.StartAdvertising(advertising);
}

fire_and_forget BluetoothBackend::on_advertisement(
		const BluetoothLEAdvertisementReceivedEventArgs &args) {
	uint64_t address = args.BluetoothAddress();
	std::string key = std::to_string(address);

	{
		std::lock_guard<std::mutex> guard(peers_mutex);
		if (peers.count(key)) {
			co_return;
		}
		peers[key] = std::make_shared<Peer>();
	}

	connect_peer(address);
	co_return;
}

fire_and_forget BluetoothBackend::connect_peer(uint64_t address) {
	std::string key = std::to_string(address);

	auto device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(address);
	if (!device) {
		std::lock_guard<std::mutex> guard(peers_mutex);
		peers.erase(key);
		co_return;
	}

	auto services = co_await device.GetGattServicesForUuidAsync(parse_guid(PP_BT_SERVICE_UUID));
	if (services.Status() != GattCommunicationStatus::Success || services.Services().Size() == 0) {
		std::lock_guard<std::mutex> guard(peers_mutex);
		peers.erase(key);
		co_return;
	}
	auto service = services.Services().GetAt(0);

	auto tx_chars = co_await service.GetCharacteristicsForUuidAsync(parse_guid(PP_BT_TX_CHAR_UUID));
	auto id_chars =
			co_await service.GetCharacteristicsForUuidAsync(parse_guid(PP_BT_IDENTITY_CHAR_UUID));
	if (tx_chars.Status() != GattCommunicationStatus::Success ||
			tx_chars.Characteristics().Size() == 0) {
		std::lock_guard<std::mutex> guard(peers_mutex);
		peers.erase(key);
		co_return;
	}

	std::string peer_id = key;
	std::string peer_name = to_string(device.Name());
	std::string peer_platform = "Windows";

	if (id_chars.Status() == GattCommunicationStatus::Success &&
			id_chars.Characteristics().Size() > 0) {
		auto read = co_await id_chars.Characteristics().GetAt(0).ReadValueAsync(
				BluetoothCacheMode::Uncached);
		if (read.Status() == GattCommunicationStatus::Success) {
			auto reader = DataReader::FromBuffer(read.Value());
			std::vector<uint8_t> raw(reader.UnconsumedBufferLength());
			if (!raw.empty()) {
				reader.ReadBytes(raw);
			}
			// The identity blob is small, flat JSON. A full parser would be
			// overkill here and would drag a dependency into a native plugin.
			std::string json(raw.begin(), raw.end());
			auto field = [&json](const char *name) -> std::string {
				std::string needle = std::string("\"") + name + "\":\"";
				size_t at = json.find(needle);
				if (at == std::string::npos) {
					return "";
				}
				at += needle.size();
				size_t end = json.find('"', at);
				if (end == std::string::npos) {
					return "";
				}
				return json.substr(at, end - at);
			};
			std::string parsed_id = field("id");
			std::string parsed_name = field("name");
			std::string parsed_platform = field("platform");
			if (!parsed_id.empty()) {
				peer_id = parsed_id;
			}
			if (!parsed_name.empty()) {
				peer_name = parsed_name;
			}
			if (!parsed_platform.empty()) {
				peer_platform = parsed_platform;
			}
		}
	}

	std::shared_ptr<Peer> peer;
	{
		std::lock_guard<std::mutex> guard(peers_mutex);
		auto found = peers.find(key);
		if (found == peers.end()) {
			co_return;
		}
		peer = found->second;
		peer->device = device;
		peer->tx = tx_chars.Characteristics().GetAt(0);
		peer->id = peer_id;
		peer->name = peer_name;
		peer->platform = peer_platform;
		// MaxPduSize includes the 3-byte ATT header.
		uint16_t pdu = service.Session().MaxPduSize();
		peer->mtu = pdu > 3 ? static_cast<uint16_t>(pdu - 3) : PP_BT_DEFAULT_CHUNK;
	}

	device.ConnectionStatusChanged(
			[this, key](BluetoothLEDevice const &sender, IInspectable const &) {
				if (sender.ConnectionStatus() != BluetoothConnectionStatus::Disconnected) {
					return;
				}
				std::string lost_id;
				{
					std::lock_guard<std::mutex> guard(peers_mutex);
					auto found = peers.find(key);
					if (found == peers.end()) {
						return;
					}
					lost_id = found->second->id;
					peers.erase(found);
				}
				owner->queue_peer_lost(String(lost_id.c_str()));
			});

	owner->queue_peer_discovered(String(key.c_str()), String(peer_id.c_str()),
			String(peer_name.c_str()), String(peer_platform.c_str()));
}

int BluetoothBackend::send(const std::string &p_handle, const std::vector<uint8_t> &p_bytes) {
	std::shared_ptr<Peer> peer;
	{
		std::lock_guard<std::mutex> guard(peers_mutex);
		auto found = peers.find(p_handle);
		if (found == peers.end() || !found->second->tx) {
			return 7; // ERR_UNAVAILABLE
		}
		peer = found->second;
		if (!peer->outbound.empty()) {
			return 12; // ERR_BUSY
		}

		// Length-prefix the envelope: BLE delivers an unframed stream of writes,
		// so the receiver has no other way to know where one project ends.
		uint32_t magic = PP_BT_CHUNK_MAGIC;
		uint32_t total = static_cast<uint32_t>(p_bytes.size());
		peer->outbound.resize(PP_BT_CHUNK_HEADER_SIZE + p_bytes.size());
		std::memcpy(peer->outbound.data(), &magic, 4);
		std::memcpy(peer->outbound.data() + 4, &total, 4);
		std::memcpy(peer->outbound.data() + PP_BT_CHUNK_HEADER_SIZE, p_bytes.data(),
				p_bytes.size());
		peer->outbound_offset = 0;
	}

	pump(peer);
	return 0; // OK
}

fire_and_forget BluetoothBackend::pump(std::shared_ptr<Peer> peer) {
	while (peer->outbound_offset < peer->outbound.size()) {
		size_t remaining = peer->outbound.size() - peer->outbound_offset;
		size_t take = std::min(static_cast<size_t>(peer->mtu), remaining);

		DataWriter writer;
		writer.WriteBytes(array_view<const uint8_t>(
				peer->outbound.data() + peer->outbound_offset,
				peer->outbound.data() + peer->outbound_offset + take));

		auto status = co_await peer->tx.WriteValueAsync(
				writer.DetachBuffer(), GattWriteOption::WriteWithoutResponse);
		if (status != GattCommunicationStatus::Success) {
			finish(peer, false, "Bluetooth write failed.");
			co_return;
		}

		peer->outbound_offset += take;
		owner->queue_transfer_progress(String(peer->id.c_str()),
				static_cast<int64_t>(peer->outbound_offset),
				static_cast<int64_t>(peer->outbound.size()));
	}

	finish(peer, true, "Sent over Bluetooth.");
}

void BluetoothBackend::finish(const std::shared_ptr<Peer> &peer, bool success,
		const std::string &message) {
	peer->outbound.clear();
	peer->outbound_offset = 0;
	owner->queue_transfer_complete(String(peer->id.c_str()), success, String(message.c_str()));
}

void BluetoothBackend::ingest(const std::string &key, const uint8_t *data, size_t length) {
	if (length == 0) {
		return;
	}

	Inbound &state = inbound[key];
	state.buffer.insert(state.buffer.end(), data, data + length);

	while (true) {
		if (state.expected == 0) {
			if (state.buffer.size() < PP_BT_CHUNK_HEADER_SIZE) {
				return;
			}
			uint32_t magic = 0;
			uint32_t total = 0;
			std::memcpy(&magic, state.buffer.data(), 4);
			std::memcpy(&total, state.buffer.data() + 4, 4);

			if (magic != PP_BT_CHUNK_MAGIC) {
				// Desynchronised; drop rather than hand up a corrupt project.
				state.buffer.clear();
				return;
			}
			state.expected = total;
			state.buffer.erase(state.buffer.begin(),
					state.buffer.begin() + PP_BT_CHUNK_HEADER_SIZE);
		}

		if (state.buffer.size() < state.expected) {
			return;
		}

		PackedByteArray bytes;
		bytes.resize(static_cast<int64_t>(state.expected));
		std::memcpy(bytes.ptrw(), state.buffer.data(), state.expected);

		state.buffer.erase(state.buffer.begin(), state.buffer.begin() + state.expected);
		state.expected = 0;

		owner->queue_data_received(String(key.c_str()), bytes);
	}
}

void BluetoothBackend::stop() {
	if (!running) {
		return;
	}
	running = false;

	if (watcher) {
		watcher.Stop();
		watcher = nullptr;
	}
	if (provider) {
		provider.StopAdvertising();
		provider = nullptr;
	}

	std::lock_guard<std::mutex> guard(peers_mutex);
	peers.clear();
	inbound.clear();
}

// --- Godot object -----------------------------------------------------------

void PixelPainterBluetooth::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start", "device_id", "device_name", "platform"),
			&PixelPainterBluetooth::start);
	ClassDB::bind_method(D_METHOD("stop"), &PixelPainterBluetooth::stop);
	ClassDB::bind_method(D_METHOD("send", "peer_handle", "bytes"), &PixelPainterBluetooth::send);
	ClassDB::bind_method(D_METHOD("poll_events"), &PixelPainterBluetooth::poll_events);

	ADD_SIGNAL(MethodInfo("peer_discovered", PropertyInfo(Variant::STRING, "handle"),
			PropertyInfo(Variant::STRING, "id"), PropertyInfo(Variant::STRING, "name"),
			PropertyInfo(Variant::STRING, "platform")));
	ADD_SIGNAL(MethodInfo("peer_lost", PropertyInfo(Variant::STRING, "id")));
	ADD_SIGNAL(MethodInfo("data_received", PropertyInfo(Variant::STRING, "id"),
			PropertyInfo(Variant::PACKED_BYTE_ARRAY, "bytes")));
	ADD_SIGNAL(MethodInfo("transfer_progress", PropertyInfo(Variant::STRING, "id"),
			PropertyInfo(Variant::INT, "sent"), PropertyInfo(Variant::INT, "total")));
	ADD_SIGNAL(MethodInfo("transfer_complete", PropertyInfo(Variant::STRING, "id"),
			PropertyInfo(Variant::BOOL, "success"), PropertyInfo(Variant::STRING, "message")));
}

PixelPainterBluetooth::PixelPainterBluetooth() {
	backend = std::make_unique<BluetoothBackend>(this);
}

PixelPainterBluetooth::~PixelPainterBluetooth() {
	if (backend) {
		backend->stop();
	}
}

void PixelPainterBluetooth::start(const String &p_device_id, const String &p_device_name,
		const String &p_platform) {
	backend->start(p_device_id.utf8().get_data(), p_device_name.utf8().get_data(),
			p_platform.utf8().get_data());
}

void PixelPainterBluetooth::stop() {
	backend->stop();
}

int PixelPainterBluetooth::send(const String &p_peer_handle, const PackedByteArray &p_bytes) {
	std::vector<uint8_t> bytes(p_bytes.size());
	if (!bytes.empty()) {
		std::memcpy(bytes.data(), p_bytes.ptr(), bytes.size());
	}
	return backend->send(p_peer_handle.utf8().get_data(), bytes);
}

void PixelPainterBluetooth::push_event(Event &&p_event) {
	std::lock_guard<std::mutex> guard(event_mutex);
	pending.push_back(std::move(p_event));
}

void PixelPainterBluetooth::queue_peer_discovered(const String &p_handle, const String &p_id,
		const String &p_name, const String &p_platform) {
	Event event;
	event.type = EventType::PEER_DISCOVERED;
	event.handle = p_handle;
	event.id = p_id;
	event.name = p_name;
	event.platform = p_platform;
	push_event(std::move(event));
}

void PixelPainterBluetooth::queue_peer_lost(const String &p_id) {
	Event event;
	event.type = EventType::PEER_LOST;
	event.id = p_id;
	push_event(std::move(event));
}

void PixelPainterBluetooth::queue_data_received(const String &p_id, const PackedByteArray &p_bytes) {
	Event event;
	event.type = EventType::DATA_RECEIVED;
	event.id = p_id;
	event.bytes = p_bytes;
	push_event(std::move(event));
}

void PixelPainterBluetooth::queue_transfer_progress(const String &p_id, int64_t p_sent,
		int64_t p_total) {
	Event event;
	event.type = EventType::TRANSFER_PROGRESS;
	event.id = p_id;
	event.sent = p_sent;
	event.total = p_total;
	push_event(std::move(event));
}

void PixelPainterBluetooth::queue_transfer_complete(const String &p_id, bool p_success,
		const String &p_message) {
	Event event;
	event.type = EventType::TRANSFER_COMPLETE;
	event.id = p_id;
	event.success = p_success;
	event.message = p_message;
	push_event(std::move(event));
}

// Drains the queue onto the main thread. WinRT's completions land on threadpool
// threads, and emitting a Godot signal from one would be a data race on the
// scene tree.
void PixelPainterBluetooth::poll_events() {
	std::vector<Event> drained;
	{
		std::lock_guard<std::mutex> guard(event_mutex);
		drained.swap(pending);
	}

	for (const Event &event : drained) {
		switch (event.type) {
			case EventType::PEER_DISCOVERED:
				emit_signal("peer_discovered", event.handle, event.id, event.name, event.platform);
				break;
			case EventType::PEER_LOST:
				emit_signal("peer_lost", event.id);
				break;
			case EventType::DATA_RECEIVED:
				emit_signal("data_received", event.id, event.bytes);
				break;
			case EventType::TRANSFER_PROGRESS:
				emit_signal("transfer_progress", event.id, event.sent, event.total);
				break;
			case EventType::TRANSFER_COMPLETE:
				emit_signal("transfer_complete", event.id, event.success, event.message);
				break;
		}
	}
}

} // namespace godot
