// Shared BLE identifiers and framing constants.
//
// Both the iOS plugin and the Windows GDExtension include this, so the two can
// never drift apart on a UUID -- which would present as "the devices simply do
// not see each other", the least debuggable failure there is.

#pragma once

#define PP_BT_SERVICE_UUID "6F5D4A10-9C3E-4B7A-8E21-1D0C5B9A7E34"

// Peers write chunked payload bytes here.
#define PP_BT_TX_CHAR_UUID "6F5D4A11-9C3E-4B7A-8E21-1D0C5B9A7E34"

// Readable JSON: {"id":"...","name":"...","platform":"..."}
#define PP_BT_IDENTITY_CHAR_UUID "6F5D4A12-9C3E-4B7A-8E21-1D0C5B9A7E34"

// Readable uint16 L2CAP PSM. Published by iOS peers only; Windows peers publish
// 0, meaning "no L2CAP channel, use chunked GATT writes".
#define PP_BT_PSM_CHAR_UUID "6F5D4A13-9C3E-4B7A-8E21-1D0C5B9A7E34"

// Every chunked GATT payload is preceded by this header so the receiver can size
// its reassembly buffer and know when the envelope is complete. BLE gives us an
// unframed byte stream; without this the receiver cannot tell one project from
// the next.
//
//   u32  magic 'PPBT'
//   u32  total payload length
//
// Little-endian, matching PPSyncProtocol.
#define PP_BT_CHUNK_MAGIC 0x54425050u
#define PP_BT_CHUNK_HEADER_SIZE 8

// Conservative default. The real value is negotiated per connection; this is only
// the fallback when the peer reports something implausible.
#define PP_BT_DEFAULT_CHUNK 180
