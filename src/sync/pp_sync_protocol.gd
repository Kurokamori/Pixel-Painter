@abstract
class_name PPSyncProtocol
extends RefCounted

## Wire format shared by every transport.
##
## Each message is a fixed 16-byte header followed by a payload:
##
##   u32  magic   'PPSY'
##   u16  version
##   u16  type    (MessageType)
##   u32  length  payload bytes that follow
##   u32  crc32   of the payload
##
## The length prefix is what makes the receiver able to stream a multi-megabyte
## project without buffering the whole thing before it knows how big it is, and
## the CRC catches a truncated or corrupted Bluetooth transfer -- which, unlike
## TCP, has no end-to-end integrity guarantee of its own.

const MAGIC: int = 0x59535050  # 'PPSY' little-endian.
const VERSION: int = 1
const HEADER_SIZE: int = 16

## Refuse absurd payloads outright rather than trying to allocate them: a
## corrupted length field must not be able to OOM the app.
const MAX_PAYLOAD: int = 256 * 1024 * 1024

enum MessageType {
	## JSON: who I am. Sent on connect, before anything else.
	HELLO,
	## Raw .pxp bytes.
	PROJECT,
	## JSON: the receiver took it.
	ACK,
	## JSON: something went wrong; carries a human-readable reason.
	REFUSE,
}


class Header:
	extends RefCounted

	var type: MessageType = MessageType.HELLO
	var length: int = 0
	var crc: int = 0
	var valid: bool = false


static func frame(type: MessageType, payload: PackedByteArray) -> PackedByteArray:
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	out.big_endian = false
	out.put_u32(MAGIC)
	out.put_u16(VERSION)
	out.put_u16(int(type))
	out.put_u32(payload.size())
	out.put_u32(_crc32(payload))
	out.put_data(payload)
	return out.data_array


static func frame_json(type: MessageType, data: Dictionary) -> PackedByteArray:
	return frame(type, JSON.stringify(data).to_utf8_buffer())


static func parse_header(bytes: PackedByteArray) -> Header:
	var header: Header = Header.new()
	if bytes.size() < HEADER_SIZE:
		return header

	var input: StreamPeerBuffer = StreamPeerBuffer.new()
	input.big_endian = false
	input.data_array = bytes

	if input.get_u32() != MAGIC:
		return header
	if input.get_u16() != VERSION:
		return header

	var type_id: int = input.get_u16()
	if type_id < 0 or type_id > int(MessageType.REFUSE):
		return header

	var length: int = input.get_u32()
	if length < 0 or length > MAX_PAYLOAD:
		return header

	header.type = type_id as MessageType
	header.length = length
	header.crc = input.get_u32()
	header.valid = true
	return header


static func verify(header: Header, payload: PackedByteArray) -> bool:
	return _crc32(payload) == header.crc


static func parse_json(payload: PackedByteArray) -> Dictionary:
	var parsed: Variant = JSON.parse_string(payload.get_string_from_utf8())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


## Standard CRC-32 (the zlib/PNG polynomial), table-driven.
static var _table: PackedInt64Array = PackedInt64Array()


static func _crc32(bytes: PackedByteArray) -> int:
	if _table.is_empty():
		_build_table()

	var crc: int = 0xFFFFFFFF
	for byte: int in bytes:
		crc = _table[(crc ^ byte) & 0xFF] ^ (crc >> 8)
	return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF


static func _build_table() -> void:
	_table.resize(256)
	for i: int in range(256):
		var value: int = i
		for bit: int in range(8):
			if (value & 1) != 0:
				value = 0xEDB88320 ^ (value >> 1)
			else:
				value >>= 1
		_table[i] = value & 0xFFFFFFFF
