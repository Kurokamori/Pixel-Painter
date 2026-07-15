class_name PPPaletteSwatch
extends Button

## One palette colour. Left click arms it as the primary, right click as the
## secondary -- matching how the paint tools read the two buttons.

signal picked(index: int, secondary: bool)

var index: int = 0

@onready var _fill: ColorRect = %Fill
@onready var _selected_border: Panel = %SelectedBorder


func setup(swatch_index: int, color: Color, swatch_name: String) -> void:
	index = swatch_index
	# The scene may not be in the tree yet when the palette panel populates, so
	# resolve the children directly rather than relying on @onready having run.
	var fill: ColorRect = get_node("%Fill")
	fill.color = color

	if swatch_name.is_empty():
		tooltip_text = "#%s" % color.to_html(color.a < 1.0).to_upper()
	else:
		tooltip_text = "%s\n#%s" % [
			swatch_name, color.to_html(color.a < 1.0).to_upper()
		]


func set_selected(value: bool) -> void:
	get_node("%SelectedBorder").visible = value


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed:
		return

	if button.button_index == MOUSE_BUTTON_LEFT:
		picked.emit(index, false)
		accept_event()
	elif button.button_index == MOUSE_BUTTON_RIGHT:
		picked.emit(index, true)
		accept_event()
