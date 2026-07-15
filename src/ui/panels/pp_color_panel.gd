class_name PPColorPanel
extends PanelContainer

## Primary/secondary swatches plus a full colour picker.
##
## The picker edits whichever slot is armed, so the eyedropper, the palette and
## the picker all write to the same place and always agree.

var app: PPAppState = null

## Which slot the picker is currently editing.
var _editing_secondary: bool = false
## Guards the picker -> settings -> picker loop.
var _syncing: bool = false

@onready var _primary: Button = %PrimaryButton
@onready var _secondary: Button = %SecondaryButton
@onready var _swap: Button = %SwapButton
@onready var _picker: ColorPicker = %Picker


func bind(state: PPAppState) -> void:
	app = state
	app.settings.changed.connect(_on_settings_changed)

	_primary.pressed.connect(_on_primary_pressed)
	_secondary.pressed.connect(_on_secondary_pressed)
	_swap.pressed.connect(_on_swap_pressed)
	_picker.color_changed.connect(_on_picker_changed)

	_on_settings_changed()


func _on_primary_pressed() -> void:
	_editing_secondary = false
	_on_settings_changed()


func _on_secondary_pressed() -> void:
	_editing_secondary = true
	_on_settings_changed()


func _on_swap_pressed() -> void:
	app.settings.swap_colors()


func _on_picker_changed(color: Color) -> void:
	if _syncing:
		return
	if _editing_secondary:
		app.settings.set_secondary(color)
	else:
		app.settings.set_primary(color)


func _on_settings_changed() -> void:
	_syncing = true

	var settings: PPToolSettings = app.settings
	_tint(_primary, settings.primary_color)
	_tint(_secondary, settings.secondary_color)

	_primary.set_pressed_no_signal(not _editing_secondary)
	_secondary.set_pressed_no_signal(_editing_secondary)

	var active: Color = (
		settings.secondary_color if _editing_secondary else settings.primary_color
	)
	if not _picker.color.is_equal_approx(active):
		_picker.color = active

	_syncing = false


## Paints a button's face with the colour it represents, and flips the label to
## whichever of black/white stays legible on it.
func _tint(button: Button, color: Color) -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(6)
	box.set_border_width_all(2)
	box.border_color = Color(0.0, 0.0, 0.0, 0.45)
	box.set_content_margin_all(8.0)

	button.add_theme_stylebox_override("normal", box)
	button.add_theme_stylebox_override("hover", box)
	button.add_theme_stylebox_override("pressed", box)

	var readable: Color = (
		Color.BLACK if color.get_luminance() > 0.5 else Color.WHITE
	)
	button.add_theme_color_override("font_color", readable)
	button.add_theme_color_override("font_hover_color", readable)
	button.add_theme_color_override("font_pressed_color", readable)
