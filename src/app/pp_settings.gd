class_name PPSettings
extends RefCounted

## Persistent application settings, stored as a ConfigFile under user://.
##
## Also the home of this installation's stable device identity, which the sync
## layer uses to recognise "the same iPad" across sessions rather than treating
## every reconnection as a new peer.
##
## A static singleton rather than an autoload: autoload names only become
## resolvable identifiers once the project is *running*, so any script naming one
## fails a static parse check. Reaching this through a `class_name` keeps the
## whole codebase compile-checkable -- and makes settings trivially injectable in
## tests.

signal settings_changed()

const CONFIG_PATH: String = "user://settings.cfg"
const MAX_RECENT: int = 12

static var _instance: PPSettings = null


static func get_instance() -> PPSettings:
	if _instance == null:
		_instance = PPSettings.new()
		_instance.load_settings()
	return _instance

# --- Identity ---
var device_id: String = ""
var device_name: String = ""

# --- Canvas ---
var show_grid: bool = false
var grid_size: Vector2i = Vector2i(8, 8)
var show_pixel_grid: bool = true
## Below this zoom the 1px grid is pure noise, so it hides itself.
var pixel_grid_min_zoom: float = 8.0
var checker_size: int = 8
var checker_light: Color = Color(0.28, 0.28, 0.31)
var checker_dark: Color = Color(0.22, 0.22, 0.25)

# --- Onion skin ---
var onion_enabled: bool = false
var onion_before: int = 1
var onion_after: int = 1
var onion_opacity: float = 0.35
var onion_before_tint: Color = Color(1.0, 0.3, 0.3)
var onion_after_tint: Color = Color(0.3, 0.7, 1.0)

# --- Input ---
## Ignore touch input while a stylus is in contact -- the classic palm-rejection
## trick, and the reason you can rest your hand on an iPad while drawing.
var palm_rejection: bool = true
## A finger drag pans instead of painting. On by default for touch devices,
## where a stylus is the drawing instrument and fingers are for navigation.
var finger_pans: bool = true
var pressure_enabled: bool = true

# --- Editor ---
var undo_limit: int = 128
var autosave_enabled: bool = true
var autosave_interval_seconds: int = 120

# --- Sync ---
var sync_enabled: bool = true
var sync_auto_accept: bool = false

var recent_files: PackedStringArray = PackedStringArray()

var _config: ConfigFile = ConfigFile.new()


func load_settings() -> void:
	var error: Error = _config.load(CONFIG_PATH)

	device_id = _config.get_value("identity", "device_id", "")
	if device_id.is_empty():
		# First run: mint a durable id. Peers key on this, so it must outlive the
		# process and survive a rename of the device.
		device_id = _generate_id()
		_config.set_value("identity", "device_id", device_id)

	device_name = _config.get_value("identity", "device_name", _default_device_name())

	show_grid = _config.get_value("canvas", "show_grid", show_grid)
	grid_size = _config.get_value("canvas", "grid_size", grid_size)
	show_pixel_grid = _config.get_value("canvas", "show_pixel_grid", show_pixel_grid)
	checker_size = _config.get_value("canvas", "checker_size", checker_size)

	onion_enabled = _config.get_value("onion", "enabled", onion_enabled)
	onion_before = _config.get_value("onion", "before", onion_before)
	onion_after = _config.get_value("onion", "after", onion_after)
	onion_opacity = _config.get_value("onion", "opacity", onion_opacity)

	palm_rejection = _config.get_value("input", "palm_rejection", palm_rejection)
	finger_pans = _config.get_value("input", "finger_pans", finger_pans)
	pressure_enabled = _config.get_value("input", "pressure_enabled", pressure_enabled)

	undo_limit = _config.get_value("editor", "undo_limit", undo_limit)
	autosave_enabled = _config.get_value("editor", "autosave_enabled", autosave_enabled)
	autosave_interval_seconds = _config.get_value(
		"editor", "autosave_interval_seconds", autosave_interval_seconds
	)

	sync_enabled = _config.get_value("sync", "enabled", sync_enabled)
	sync_auto_accept = _config.get_value("sync", "auto_accept", sync_auto_accept)

	recent_files = _config.get_value("files", "recent", PackedStringArray())

	if error != OK:
		save_settings()


func save_settings() -> void:
	_config.set_value("identity", "device_id", device_id)
	_config.set_value("identity", "device_name", device_name)

	_config.set_value("canvas", "show_grid", show_grid)
	_config.set_value("canvas", "grid_size", grid_size)
	_config.set_value("canvas", "show_pixel_grid", show_pixel_grid)
	_config.set_value("canvas", "checker_size", checker_size)

	_config.set_value("onion", "enabled", onion_enabled)
	_config.set_value("onion", "before", onion_before)
	_config.set_value("onion", "after", onion_after)
	_config.set_value("onion", "opacity", onion_opacity)

	_config.set_value("input", "palm_rejection", palm_rejection)
	_config.set_value("input", "finger_pans", finger_pans)
	_config.set_value("input", "pressure_enabled", pressure_enabled)

	_config.set_value("editor", "undo_limit", undo_limit)
	_config.set_value("editor", "autosave_enabled", autosave_enabled)
	_config.set_value("editor", "autosave_interval_seconds", autosave_interval_seconds)

	_config.set_value("sync", "enabled", sync_enabled)
	_config.set_value("sync", "auto_accept", sync_auto_accept)

	_config.set_value("files", "recent", recent_files)

	_config.save(CONFIG_PATH)
	settings_changed.emit()


func add_recent_file(path: String) -> void:
	if path.is_empty():
		return
	var updated: PackedStringArray = PackedStringArray([path])
	for existing: String in recent_files:
		if existing == path:
			continue
		if updated.size() >= MAX_RECENT:
			break
		updated.append(existing)
	recent_files = updated
	save_settings()


func clear_recent_files() -> void:
	recent_files = PackedStringArray()
	save_settings()


func _generate_id() -> String:
	# Godot has no UUID primitive; a crypto-random 16-byte hex string is both
	# sufficient and collision-free in practice for a LAN peer id.
	var crypto: Crypto = Crypto.new()
	return crypto.generate_random_bytes(16).hex_encode()


func _default_device_name() -> String:
	var model: String = OS.get_model_name()
	if not model.is_empty() and model != "GenericDevice":
		return model
	var host: String = OS.get_environment("COMPUTERNAME")
	if host.is_empty():
		host = OS.get_environment("HOSTNAME")
	if host.is_empty():
		host = "%s Device" % OS.get_name()
	return host
