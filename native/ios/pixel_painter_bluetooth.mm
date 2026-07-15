// iOS Bluetooth transport, built on CoreBluetooth.
//
// Every device runs in *both* roles at once:
//
//   Peripheral  advertises the Pixel Painter service, publishes an identity
//               characteristic and an L2CAP PSM, and accepts inbound bytes.
//   Central     scans for the same service, connects, reads the peer's identity,
//               and sends outbound bytes.
//
// Running both is what lets any device send to any other without one of them
// having to be nominated "the server" first, which would be a terrible thing to
// ask of someone who just wants to move a drawing to their iPad.
//
// Transfer takes the fastest route the peer supports:
//
//   * L2CAP connection-oriented channel (~1-2 Mbit/s) when the peer publishes a
//     PSM -- i.e. another Apple device.
//   * Chunked GATT characteristic writes otherwise (Windows), which is slow but
//     universal. See native/README.md for why there is no better option.

#import <CoreBluetooth/CoreBluetooth.h>
#import <Foundation/Foundation.h>

#include "pixel_painter_bluetooth.h"

#include "core/object/callable_method_pointer.h"
#include "core/os/os.h"

#include "../shared/pp_bluetooth_uuids.h"

// --- Peer bookkeeping -------------------------------------------------------

@interface PPPeerRecord : NSObject
@property(nonatomic, strong) CBPeripheral *peripheral;
@property(nonatomic, strong) CBL2CAPChannel *channel;
@property(nonatomic, strong) CBCharacteristic *txCharacteristic;
@property(nonatomic, copy) NSString *peerId;
@property(nonatomic, copy) NSString *peerName;
@property(nonatomic, copy) NSString *peerPlatform;
@property(nonatomic, assign) UInt16 psm;

// Outbound
@property(nonatomic, strong) NSMutableData *outbound;
@property(nonatomic, assign) NSUInteger outboundOffset;

// Inbound reassembly
@property(nonatomic, strong) NSMutableData *inbound;
@property(nonatomic, assign) UInt32 expected;
@end

@implementation PPPeerRecord
- (instancetype)init {
	self = [super init];
	if (self) {
		_inbound = [NSMutableData data];
		_outbound = nil;
		_outboundOffset = 0;
		_expected = 0;
		_psm = 0;
	}
	return self;
}
@end

// --- Controller -------------------------------------------------------------

@interface PPBluetoothController : NSObject <CBCentralManagerDelegate,
											 CBPeripheralDelegate,
											 CBPeripheralManagerDelegate,
											 NSStreamDelegate>

@property(nonatomic, strong) CBCentralManager *central;
@property(nonatomic, strong) CBPeripheralManager *peripheral;
@property(nonatomic, strong) CBMutableService *service;
@property(nonatomic, strong) CBMutableCharacteristic *txCharacteristic;
@property(nonatomic, strong) CBMutableCharacteristic *identityCharacteristic;
@property(nonatomic, strong) CBMutableCharacteristic *psmCharacteristic;

@property(nonatomic, copy) NSString *deviceId;
@property(nonatomic, copy) NSString *deviceName;
@property(nonatomic, copy) NSString *devicePlatform;

@property(nonatomic, assign) UInt16 publishedPsm;
@property(nonatomic, strong) NSMutableDictionary<NSString *, PPPeerRecord *> *peers;

// Inbound reassembly for peers that write to us as a GATT central.
@property(nonatomic, strong) NSMutableDictionary<NSString *, PPPeerRecord *> *inboundPeers;

@property(nonatomic, assign) PixelPainterBluetooth *owner;
@property(nonatomic, assign) BOOL running;

- (void)startWithId:(NSString *)deviceId name:(NSString *)name platform:(NSString *)platform;
- (void)stop;
- (int)sendTo:(NSString *)handle bytes:(NSData *)data;
@end

@implementation PPBluetoothController

- (instancetype)init {
	self = [super init];
	if (self) {
		_peers = [NSMutableDictionary dictionary];
		_inboundPeers = [NSMutableDictionary dictionary];
		_publishedPsm = 0;
		_running = NO;
	}
	return self;
}

- (void)startWithId:(NSString *)deviceId name:(NSString *)name platform:(NSString *)platform {
	if (_running) {
		return;
	}
	_deviceId = deviceId;
	_deviceName = name;
	_devicePlatform = platform;
	_running = YES;

	_central = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
	_peripheral = [[CBPeripheralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
}

- (void)stop {
	if (!_running) {
		return;
	}
	_running = NO;

	[_central stopScan];
	[_peripheral stopAdvertising];
	[_peripheral removeAllServices];

	for (PPPeerRecord *record in _peers.allValues) {
		if (record.peripheral) {
			[_central cancelPeripheralConnection:record.peripheral];
		}
	}
	[_peers removeAllObjects];
	[_inboundPeers removeAllObjects];

	_central = nil;
	_peripheral = nil;
}

- (NSData *)identityPayload {
	NSDictionary *identity = @{
		@"id" : _deviceId ?: @"",
		@"name" : _deviceName ?: @"",
		@"platform" : _devicePlatform ?: @"iOS",
	};
	return [NSJSONSerialization dataWithJSONObject:identity options:0 error:nil];
}

// --- Peripheral role ---

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
	if (peripheral.state != CBManagerStatePoweredOn) {
		return;
	}

	// Publishing an L2CAP channel gives Apple-to-Apple transfers a fast path. The
	// PSM is assigned by the system and handed back asynchronously, so it is
	// advertised through a characteristic rather than in the advertisement itself
	// (which has no room for it anyway).
	[peripheral publishL2CAPChannelWithEncryption:YES];

	CBUUID *serviceUUID = [CBUUID UUIDWithString:@PP_BT_SERVICE_UUID];

	_txCharacteristic = [[CBMutableCharacteristic alloc]
			initWithType:[CBUUID UUIDWithString:@PP_BT_TX_CHAR_UUID]
			  properties:CBCharacteristicPropertyWrite | CBCharacteristicPropertyWriteWithoutResponse
				   value:nil
			 permissions:CBAttributePermissionsWriteable];

	_identityCharacteristic = [[CBMutableCharacteristic alloc]
			initWithType:[CBUUID UUIDWithString:@PP_BT_IDENTITY_CHAR_UUID]
			  properties:CBCharacteristicPropertyRead
				   value:[self identityPayload]
			 permissions:CBAttributePermissionsReadable];

	UInt16 psm = _publishedPsm;
	_psmCharacteristic = [[CBMutableCharacteristic alloc]
			initWithType:[CBUUID UUIDWithString:@PP_BT_PSM_CHAR_UUID]
			  properties:CBCharacteristicPropertyRead
				   value:[NSData dataWithBytes:&psm length:sizeof(psm)]
			 permissions:CBAttributePermissionsReadable];

	_service = [[CBMutableService alloc] initWithType:serviceUUID primary:YES];
	_service.characteristics = @[ _txCharacteristic, _identityCharacteristic, _psmCharacteristic ];

	[peripheral addService:_service];
	[peripheral startAdvertising:@{
		CBAdvertisementDataServiceUUIDsKey : @[ serviceUUID ],
		CBAdvertisementDataLocalNameKey : _deviceName ?: @"Pixel Painter",
	}];
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
		didPublishL2CAPChannel:(CBL2CAPPSM)psm
						 error:(NSError *)error {
	if (error) {
		return;
	}
	_publishedPsm = (UInt16)psm;

	// The service may already be live with a stale PSM of 0; re-publish so peers
	// that read the characteristic get the real value.
	if (_psmCharacteristic) {
		UInt16 value = _publishedPsm;
		_psmCharacteristic.value = [NSData dataWithBytes:&value length:sizeof(value)];
	}
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
		didOpenL2CAPChannel:(CBL2CAPChannel *)channel
					  error:(NSError *)error {
	if (error || !channel) {
		return;
	}
	channel.inputStream.delegate = self;
	channel.outputStream.delegate = self;
	[channel.inputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
	[channel.outputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
	[channel.inputStream open];
	[channel.outputStream open];
}

// Inbound GATT writes: a peer that cannot use L2CAP (i.e. Windows) chunks the
// envelope into characteristic writes, which land here.
- (void)peripheralManager:(CBPeripheralManager *)peripheral
	didReceiveWriteRequests:(NSArray<CBATTRequest *> *)requests {
	for (CBATTRequest *request in requests) {
		if (![request.characteristic.UUID isEqual:_txCharacteristic.UUID]) {
			[peripheral respondToRequest:request withResult:CBATTErrorWriteNotPermitted];
			continue;
		}

		NSString *key = request.central.identifier.UUIDString;
		PPPeerRecord *record = _inboundPeers[key];
		if (!record) {
			record = [[PPPeerRecord alloc] init];
			record.peerId = key;
			record.peerName = @"Bluetooth Device";
			record.peerPlatform = @"unknown";
			_inboundPeers[key] = record;
		}

		[self ingest:request.value into:record];
	}

	if (requests.count > 0) {
		[peripheral respondToRequest:requests.firstObject withResult:CBATTErrorSuccess];
	}
}

// --- Central role ---

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
	if (central.state != CBManagerStatePoweredOn) {
		return;
	}
	[central scanForPeripheralsWithServices:@[ [CBUUID UUIDWithString:@PP_BT_SERVICE_UUID] ]
									options:@{ CBCentralManagerScanOptionAllowDuplicatesKey : @NO }];
}

- (void)centralManager:(CBCentralManager *)central
	 didDiscoverPeripheral:(CBPeripheral *)peripheral
		 advertisementData:(NSDictionary<NSString *, id> *)advertisementData
					  RSSI:(NSNumber *)RSSI {
	NSString *key = peripheral.identifier.UUIDString;
	if (_peers[key]) {
		return;
	}

	PPPeerRecord *record = [[PPPeerRecord alloc] init];
	record.peripheral = peripheral;
	record.peerId = key;
	record.peerName = advertisementData[CBAdvertisementDataLocalNameKey] ?: @"Bluetooth Device";
	record.peerPlatform = @"unknown";
	_peers[key] = record;

	peripheral.delegate = self;
	[central connectPeripheral:peripheral options:nil];
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
	[peripheral discoverServices:@[ [CBUUID UUIDWithString:@PP_BT_SERVICE_UUID] ]];
}

- (void)centralManager:(CBCentralManager *)central
	didDisconnectPeripheral:(CBPeripheral *)peripheral
					  error:(NSError *)error {
	NSString *key = peripheral.identifier.UUIDString;
	PPPeerRecord *record = _peers[key];
	if (!record) {
		return;
	}
	[_peers removeObjectForKey:key];

	if (_owner) {
		_owner->on_peer_lost(String::utf8(record.peerId.UTF8String));
	}
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
	if (error) {
		return;
	}
	for (CBService *service in peripheral.services) {
		[peripheral discoverCharacteristics:nil forService:service];
	}
}

- (void)peripheral:(CBPeripheral *)peripheral
	didDiscoverCharacteristicsForService:(CBService *)service
								   error:(NSError *)error {
	if (error) {
		return;
	}
	PPPeerRecord *record = _peers[peripheral.identifier.UUIDString];
	if (!record) {
		return;
	}

	for (CBCharacteristic *characteristic in service.characteristics) {
		if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:@PP_BT_TX_CHAR_UUID]]) {
			record.txCharacteristic = characteristic;
		} else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:@PP_BT_IDENTITY_CHAR_UUID]]) {
			[peripheral readValueForCharacteristic:characteristic];
		} else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:@PP_BT_PSM_CHAR_UUID]]) {
			[peripheral readValueForCharacteristic:characteristic];
		}
	}
}

- (void)peripheral:(CBPeripheral *)peripheral
	didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
							  error:(NSError *)error {
	if (error) {
		return;
	}
	PPPeerRecord *record = _peers[peripheral.identifier.UUIDString];
	if (!record) {
		return;
	}

	if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:@PP_BT_IDENTITY_CHAR_UUID]]) {
		NSDictionary *identity = [NSJSONSerialization JSONObjectWithData:characteristic.value
																options:0
																  error:nil];
		if ([identity isKindOfClass:NSDictionary.class]) {
			record.peerId = identity[@"id"] ?: record.peerId;
			record.peerName = identity[@"name"] ?: record.peerName;
			record.peerPlatform = identity[@"platform"] ?: @"unknown";
		}

		// Only surface the peer once we know who it actually is -- announcing a
		// row called "Bluetooth Device" that renames itself a second later is
		// worse than a beat of latency.
		if (_owner) {
			_owner->on_peer_discovered(
					String::utf8(peripheral.identifier.UUIDString.UTF8String),
					String::utf8(record.peerId.UTF8String),
					String::utf8(record.peerName.UTF8String),
					String::utf8(record.peerPlatform.UTF8String));
		}
	} else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:@PP_BT_PSM_CHAR_UUID]]) {
		UInt16 psm = 0;
		if (characteristic.value.length >= sizeof(UInt16)) {
			[characteristic.value getBytes:&psm length:sizeof(psm)];
		}
		record.psm = psm;
	}
}

- (void)peripheral:(CBPeripheral *)peripheral
	didOpenL2CAPChannel:(CBL2CAPChannel *)channel
				  error:(NSError *)error {
	PPPeerRecord *record = _peers[peripheral.identifier.UUIDString];
	if (error || !record) {
		if (record) {
			// L2CAP refused: fall back to the slow-but-universal GATT path rather
			// than failing the transfer outright.
			[self pumpGattWrites:record];
		}
		return;
	}

	record.channel = channel;
	channel.inputStream.delegate = self;
	channel.outputStream.delegate = self;
	[channel.inputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
	[channel.outputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
	[channel.inputStream open];
	[channel.outputStream open];
}

- (void)peripheralIsReadyToSendWriteWithoutResponse:(CBPeripheral *)peripheral {
	PPPeerRecord *record = _peers[peripheral.identifier.UUIDString];
	if (record) {
		[self pumpGattWrites:record];
	}
}

// --- Sending ---

- (int)sendTo:(NSString *)handle bytes:(NSData *)data {
	PPPeerRecord *record = _peers[handle];
	if (!record) {
		return 7; // ERR_UNAVAILABLE
	}
	if (record.outbound) {
		return 12; // ERR_BUSY
	}

	// Prefix the envelope with its own length so the receiver can size its
	// reassembly buffer -- BLE hands over an unframed stream of fragments.
	NSMutableData *framed = [NSMutableData data];
	UInt32 magic = PP_BT_CHUNK_MAGIC;
	UInt32 total = (UInt32)data.length;
	[framed appendBytes:&magic length:sizeof(magic)];
	[framed appendBytes:&total length:sizeof(total)];
	[framed appendData:data];

	record.outbound = framed;
	record.outboundOffset = 0;

	if (record.psm != 0 && !record.channel) {
		[record.peripheral openL2CAPChannel:record.psm];
		return 0; // Sending continues once the channel opens.
	}

	if (record.channel) {
		[self pumpL2CAP:record];
	} else {
		[self pumpGattWrites:record];
	}
	return 0; // OK
}

- (void)pumpGattWrites:(PPPeerRecord *)record {
	if (!record.outbound || !record.txCharacteristic || !record.peripheral) {
		return;
	}

	NSUInteger mtu = [record.peripheral maximumWriteValueLengthForType:
										CBCharacteristicWriteWithoutResponse];
	if (mtu == 0) {
		mtu = PP_BT_DEFAULT_CHUNK;
	}

	while (record.outboundOffset < record.outbound.length) {
		if (![record.peripheral canSendWriteWithoutResponse]) {
			// The queue is full; peripheralIsReadyToSendWriteWithoutResponse:
			// will call us back.
			return;
		}

		NSUInteger remaining = record.outbound.length - record.outboundOffset;
		NSUInteger take = MIN(mtu, remaining);
		NSData *chunk = [record.outbound subdataWithRange:NSMakeRange(record.outboundOffset, take)];

		[record.peripheral writeValue:chunk
					forCharacteristic:record.txCharacteristic
								 type:CBCharacteristicWriteWithoutResponse];
		record.outboundOffset += take;

		if (_owner) {
			_owner->on_transfer_progress(String::utf8(record.peerId.UTF8String),
					(int)record.outboundOffset, (int)record.outbound.length);
		}
	}

	[self finishSend:record success:YES message:@"Sent over Bluetooth."];
}

- (void)pumpL2CAP:(PPPeerRecord *)record {
	if (!record.outbound || !record.channel) {
		return;
	}
	NSOutputStream *stream = record.channel.outputStream;

	while (record.outboundOffset < record.outbound.length && stream.hasSpaceAvailable) {
		const uint8_t *bytes = (const uint8_t *)record.outbound.bytes;
		NSInteger written = [stream write:bytes + record.outboundOffset
							   maxLength:record.outbound.length - record.outboundOffset];
		if (written <= 0) {
			[self finishSend:record success:NO message:@"Bluetooth write failed."];
			return;
		}
		record.outboundOffset += (NSUInteger)written;

		if (_owner) {
			_owner->on_transfer_progress(String::utf8(record.peerId.UTF8String),
					(int)record.outboundOffset, (int)record.outbound.length);
		}
	}

	if (record.outboundOffset >= record.outbound.length) {
		[self finishSend:record success:YES message:@"Sent over Bluetooth."];
	}
}

- (void)finishSend:(PPPeerRecord *)record success:(BOOL)success message:(NSString *)message {
	record.outbound = nil;
	record.outboundOffset = 0;
	if (_owner) {
		_owner->on_transfer_complete(String::utf8(record.peerId.UTF8String), success,
				String::utf8(message.UTF8String));
	}
}

// --- Receiving ---

// Accumulates fragments and emits exactly one data_received per complete envelope.
- (void)ingest:(NSData *)fragment into:(PPPeerRecord *)record {
	if (!fragment.length) {
		return;
	}
	[record.inbound appendData:fragment];

	while (true) {
		if (record.expected == 0) {
			if (record.inbound.length < PP_BT_CHUNK_HEADER_SIZE) {
				return;
			}
			UInt32 magic = 0;
			UInt32 total = 0;
			[record.inbound getBytes:&magic range:NSMakeRange(0, 4)];
			[record.inbound getBytes:&total range:NSMakeRange(4, 4)];

			if (magic != PP_BT_CHUNK_MAGIC) {
				// Desynchronised beyond recovery; drop the buffer rather than
				// hand Godot a corrupt project.
				[record.inbound setLength:0];
				return;
			}
			record.expected = total;
			[record.inbound replaceBytesInRange:NSMakeRange(0, PP_BT_CHUNK_HEADER_SIZE)
									  withBytes:NULL
										 length:0];
		}

		if (record.inbound.length < record.expected) {
			return;
		}

		NSData *envelope = [record.inbound subdataWithRange:NSMakeRange(0, record.expected)];
		[record.inbound replaceBytesInRange:NSMakeRange(0, record.expected)
								  withBytes:NULL
									 length:0];
		record.expected = 0;

		if (_owner) {
			PackedByteArray bytes;
			bytes.resize((int)envelope.length);
			memcpy(bytes.ptrw(), envelope.bytes, envelope.length);
			_owner->on_data_received(String::utf8(record.peerId.UTF8String), bytes);
		}
	}
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event {
	PPPeerRecord *found = nil;
	for (PPPeerRecord *record in _peers.allValues) {
		if (record.channel.inputStream == stream || record.channel.outputStream == stream) {
			found = record;
			break;
		}
	}

	switch (event) {
		case NSStreamEventHasBytesAvailable: {
			if (!found) {
				return;
			}
			uint8_t buffer[4096];
			NSInteger read = [(NSInputStream *)stream read:buffer maxLength:sizeof(buffer)];
			if (read > 0) {
				[self ingest:[NSData dataWithBytes:buffer length:read] into:found];
			}
			break;
		}
		case NSStreamEventHasSpaceAvailable: {
			if (found) {
				[self pumpL2CAP:found];
			}
			break;
		}
		case NSStreamEventErrorOccurred:
		case NSStreamEventEndEncountered: {
			if (found && found.outbound) {
				[self finishSend:found success:NO message:@"Bluetooth connection closed."];
			}
			break;
		}
		default:
			break;
	}
}

@end

// --- Godot bridge -----------------------------------------------------------

PixelPainterBluetooth *PixelPainterBluetooth::singleton = nullptr;

PixelPainterBluetooth *PixelPainterBluetooth::get_singleton() {
	return singleton;
}

void PixelPainterBluetooth::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start", "device_id", "device_name", "platform"),
			&PixelPainterBluetooth::start);
	ClassDB::bind_method(D_METHOD("stop"), &PixelPainterBluetooth::stop);
	ClassDB::bind_method(D_METHOD("send", "peer_handle", "bytes"), &PixelPainterBluetooth::send);

	ADD_SIGNAL(MethodInfo("peer_discovered",
			PropertyInfo(Variant::STRING, "handle"),
			PropertyInfo(Variant::STRING, "id"),
			PropertyInfo(Variant::STRING, "name"),
			PropertyInfo(Variant::STRING, "platform")));
	ADD_SIGNAL(MethodInfo("peer_lost", PropertyInfo(Variant::STRING, "id")));
	ADD_SIGNAL(MethodInfo("data_received",
			PropertyInfo(Variant::STRING, "id"),
			PropertyInfo(Variant::PACKED_BYTE_ARRAY, "bytes")));
	ADD_SIGNAL(MethodInfo("transfer_progress",
			PropertyInfo(Variant::STRING, "id"),
			PropertyInfo(Variant::INT, "sent"),
			PropertyInfo(Variant::INT, "total")));
	ADD_SIGNAL(MethodInfo("transfer_complete",
			PropertyInfo(Variant::STRING, "id"),
			PropertyInfo(Variant::BOOL, "success"),
			PropertyInfo(Variant::STRING, "message")));
}

PixelPainterBluetooth::PixelPainterBluetooth() {
	singleton = this;
	PPBluetoothController *c = [[PPBluetoothController alloc] init];
	c.owner = this;
	controller = (__bridge_retained void *)c;
}

PixelPainterBluetooth::~PixelPainterBluetooth() {
	if (controller) {
		PPBluetoothController *c = (__bridge_transfer PPBluetoothController *)controller;
		[c stop];
		controller = nullptr;
	}
	singleton = nullptr;
}

void PixelPainterBluetooth::start(const String &p_device_id, const String &p_device_name,
		const String &p_platform) {
	PPBluetoothController *c = (__bridge PPBluetoothController *)controller;
	[c startWithId:[NSString stringWithUTF8String:p_device_id.utf8().get_data()]
			  name:[NSString stringWithUTF8String:p_device_name.utf8().get_data()]
		  platform:[NSString stringWithUTF8String:p_platform.utf8().get_data()]];
}

void PixelPainterBluetooth::stop() {
	PPBluetoothController *c = (__bridge PPBluetoothController *)controller;
	[c stop];
}

int PixelPainterBluetooth::send(const String &p_peer_handle, const PackedByteArray &p_bytes) {
	PPBluetoothController *c = (__bridge PPBluetoothController *)controller;
	NSData *data = [NSData dataWithBytes:p_bytes.ptr() length:p_bytes.size()];
	return [c sendTo:[NSString stringWithUTF8String:p_peer_handle.utf8().get_data()] bytes:data];
}

// CoreBluetooth delivers on the main queue (we asked it to), so these are already
// on Godot's thread and can emit directly.

void PixelPainterBluetooth::on_peer_discovered(const String &p_handle, const String &p_id,
		const String &p_name, const String &p_platform) {
	emit_signal("peer_discovered", p_handle, p_id, p_name, p_platform);
}

void PixelPainterBluetooth::on_peer_lost(const String &p_id) {
	emit_signal("peer_lost", p_id);
}

void PixelPainterBluetooth::on_data_received(const String &p_id, const PackedByteArray &p_bytes) {
	emit_signal("data_received", p_id, p_bytes);
}

void PixelPainterBluetooth::on_transfer_progress(const String &p_id, int p_sent, int p_total) {
	emit_signal("transfer_progress", p_id, p_sent, p_total);
}

void PixelPainterBluetooth::on_transfer_complete(const String &p_id, bool p_success,
		const String &p_message) {
	emit_signal("transfer_complete", p_id, p_success, p_message);
}
