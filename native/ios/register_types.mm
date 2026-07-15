// Godot iOS plugin registration.
//
// Godot calls these two symbols when the plugin is enabled in the iOS export
// preset. Registering the singleton here is what makes
// Engine.has_singleton("PixelPainterBluetooth") true in GDScript -- and that check
// is exactly what PPBluetoothTransport uses to decide whether Bluetooth is
// available at all.

#include "register_types.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"

#include "pixel_painter_bluetooth.h"

PixelPainterBluetooth *plugin_instance = nullptr;

void pixel_painter_bluetooth_init() {
	GDREGISTER_CLASS(PixelPainterBluetooth);
	plugin_instance = memnew(PixelPainterBluetooth);
	Engine::get_singleton()->add_singleton(
			Engine::Singleton("PixelPainterBluetooth", plugin_instance));
}

void pixel_painter_bluetooth_deinit() {
	if (plugin_instance) {
		memdelete(plugin_instance);
		plugin_instance = nullptr;
	}
}
