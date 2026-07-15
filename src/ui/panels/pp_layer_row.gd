class_name PPLayerRow
extends PanelContainer

## One row of the layers list.
##
## Emits intent, never mutates the document: every change goes back through the
## panel so it lands on the undo stack.

signal selected(layer_index: int)
signal visibility_toggled(layer_index: int, visible: bool)
signal lock_toggled(layer_index: int, locked: bool)
## Named layer_renamed, not renamed: Node already emits a `renamed` signal.
signal layer_renamed(layer_index: int, name: String)

var layer_index: int = 0

@onready var _visible_button: Button = %VisibleButton
@onready var _lock_button: Button = %LockButton
@onready var _name_button: Button = %NameButton
@onready var _name_edit: LineEdit = %NameEdit


func _ready() -> void:
	_visible_button.toggled.connect(
		func(on: bool) -> void: visibility_toggled.emit(layer_index, on)
	)
	_lock_button.toggled.connect(
		func(on: bool) -> void: lock_toggled.emit(layer_index, on)
	)
	_name_button.pressed.connect(
		func() -> void: selected.emit(layer_index)
	)
	_name_button.gui_input.connect(_on_name_input)
	_name_edit.text_submitted.connect(_on_rename_submitted)
	_name_edit.focus_exited.connect(_end_rename)


func setup(index: int, layer: PPLayer, active: bool) -> void:
	layer_index = index

	var visible_button: Button = get_node("%VisibleButton")
	var lock_button: Button = get_node("%LockButton")
	var name_button: Button = get_node("%NameButton")

	visible_button.set_pressed_no_signal(layer.visible)
	visible_button.text = "◉" if layer.visible else "○"

	lock_button.set_pressed_no_signal(layer.locked)
	lock_button.text = "🔒" if layer.locked else "○"

	name_button.text = layer.name
	if layer.opacity < 1.0 or layer.blend_mode != PPTypes.BlendMode.NORMAL:
		name_button.text = "%s  ·  %s %d%%" % [
			layer.name,
			PPTypes.blend_mode_name(layer.blend_mode),
			int(round(layer.opacity * 100.0)),
		]

	_highlight(active)


func _highlight(active: bool) -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.set_corner_radius_all(5)
	box.set_content_margin_all(4.0)
	if active:
		box.bg_color = Color(0.161, 0.353, 0.588, 1.0)
		box.set_border_width_all(1)
		box.border_color = Color(0.29, 0.62, 1.0, 1.0)
	else:
		box.bg_color = Color(0.125, 0.125, 0.157, 1.0)
	add_theme_stylebox_override("panel", box)


func _on_name_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.double_click and button.button_index == MOUSE_BUTTON_LEFT:
		_begin_rename()


func _begin_rename() -> void:
	_name_edit.text = _name_button.text
	_name_button.visible = false
	_name_edit.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()


func _on_rename_submitted(text: String) -> void:
	var trimmed: String = text.strip_edges()
	if not trimmed.is_empty():
		layer_renamed.emit(layer_index, trimmed)
	_end_rename()


func _end_rename() -> void:
	_name_edit.visible = false
	_name_button.visible = true
