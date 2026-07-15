class_name PPPaletteCommand
extends PPCommand

## Swaps the whole palette. Palettes are small (a few hundred colours at most),
## so snapshotting beats tracking individual swatch edits, and it makes "load
## palette" and "edit one swatch" the same undoable operation.

var _before: PPPalette = null
var _after: PPPalette = null


static func create(
	current: PPPalette, replacement: PPPalette, label_text: String
) -> PPPaletteCommand:
	var command: PPPaletteCommand = PPPaletteCommand.new()
	command.label = label_text
	command._before = current.duplicate_palette()
	command._after = replacement.duplicate_palette()
	return command


func redo(document: PPDocument) -> void:
	_write(document, _after)


func undo(document: PPDocument) -> void:
	_write(document, _before)


func is_structural() -> bool:
	return true


func _write(document: PPDocument, source: PPPalette) -> void:
	var palette: PPPalette = document.sprite.palette
	palette.name = source.name
	palette.colors = source.colors.duplicate()
	palette.color_names = source.color_names.duplicate()
	palette.palette_changed.emit()
