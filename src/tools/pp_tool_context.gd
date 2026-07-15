class_name PPToolContext
extends RefCounted

## Everything a tool is allowed to touch. Tools never reach for globals; they
## get exactly this, which keeps them unit-testable without a scene tree.

signal overlay_changed()
signal status_changed(text: String)

var document: PPDocument = null
var settings: PPToolSettings = null


static func create(target: PPDocument, tool_settings: PPToolSettings) -> PPToolContext:
	var context: PPToolContext = PPToolContext.new()
	context.document = target
	context.settings = tool_settings
	return context


## The pixels a sampling tool (bucket, wand, eyedropper) should read: either the
## active cel alone, or the flattened frame when "sample all layers" is on.
func get_sample_buffer() -> PackedByteArray:
	if settings.sample_all_layers:
		return PPCompositor.flatten_frame(
			document.sprite, document.active_frame
		).get_data()
	var cel: PPCel = document.get_active_cel()
	if cel == null or cel.image == null:
		var empty: PackedByteArray = PackedByteArray()
		empty.resize(document.sprite.size.x * document.sprite.size.y * PPTypes.BPP)
		return empty
	return cel.image.get_data()


## The colour a stroke should lay down: primary normally, secondary for a
## right-click or an inverted (eraser-end) stylus.
func color_for(pointer: PPPointer) -> Color:
	if pointer.secondary:
		return settings.secondary_color
	return settings.primary_color


func push(command: PPCommand) -> void:
	document.history.push(command)


func push_applied(command: PPCommand) -> void:
	document.history.push_applied(command)


func request_overlay_redraw() -> void:
	overlay_changed.emit()


func set_status(text: String) -> void:
	status_changed.emit(text)


func in_bounds(cell: Vector2i) -> bool:
	return document.sprite.get_bounds().has_point(cell)
