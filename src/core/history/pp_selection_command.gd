class_name PPSelectionCommand
extends PPCommand

## Swaps the selection mask. Selection changes are undoable in Aseprite and are
## expected to be here too -- losing a painstaking lasso to a stray click is
## exactly the kind of thing undo exists for.

var _before: PackedByteArray = PackedByteArray()
var _after: PackedByteArray = PackedByteArray()
var _raw_size: int = 0


## Before and after are passed explicitly rather than read from the live
## selection, because the selection tools update the mask *during* the drag for
## immediate marching-ants feedback -- by release time the document no longer
## holds the "before" state, so the tool has to carry it.
static func create(
	before_mask: PackedByteArray, after_mask: PackedByteArray, label_text: String
) -> PPSelectionCommand:
	if before_mask == after_mask:
		return null
	var command: PPSelectionCommand = PPSelectionCommand.new()
	command.label = label_text
	command._raw_size = before_mask.size()
	command._before = before_mask.compress(FileAccess.COMPRESSION_ZSTD)
	command._after = after_mask.compress(FileAccess.COMPRESSION_ZSTD)
	return command


func redo(document: PPDocument) -> void:
	_write(document, _after)


func undo(document: PPDocument) -> void:
	_write(document, _before)


func get_dirty_rect(document: PPDocument) -> Rect2i:
	return document.sprite.get_bounds()


func _write(document: PPDocument, compressed: PackedByteArray) -> void:
	var bytes: PackedByteArray = compressed.decompress(
		_raw_size, FileAccess.COMPRESSION_ZSTD
	)
	document.selection.set_mask(bytes)
