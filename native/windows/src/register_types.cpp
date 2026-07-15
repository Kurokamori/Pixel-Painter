// GDExtension entry point.
//
// Registering the singleton here is what makes
// Engine.has_singleton("PixelPainterBluetooth") true in GDScript, which is the
// exact check PPBluetoothTransport uses to decide whether Bluetooth exists at all.

#include "register_types.h"

#include <gdextension_interface.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "pixel_painter_bluetooth.h"

using namespace godot;

static PixelPainterBluetooth *bluetooth_singleton = nullptr;

void initialize_pixel_painter_bluetooth(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	GDREGISTER_CLASS(PixelPainterBluetooth);

	bluetooth_singleton = memnew(PixelPainterBluetooth);
	Engine::get_singleton()->register_singleton("PixelPainterBluetooth", bluetooth_singleton);
}

void uninitialize_pixel_painter_bluetooth(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	if (bluetooth_singleton) {
		Engine::get_singleton()->unregister_singleton("PixelPainterBluetooth");
		memdelete(bluetooth_singleton);
		bluetooth_singleton = nullptr;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT pixel_painter_bluetooth_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_pixel_painter_bluetooth);
	init_obj.register_terminator(uninitialize_pixel_painter_bluetooth);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
