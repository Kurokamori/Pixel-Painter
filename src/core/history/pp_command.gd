@abstract
class_name PPCommand
extends RefCounted

## One undoable unit of work.
##
## Commands are constructed already knowing both the "before" and "after" state,
## so redo() is not merely "do it again" -- it restores a captured result. That
## keeps redo exact even for operations that are not deterministic functions of
## the document (flood fill with a random dither, for instance).

var label: String = "Edit"


@abstract func redo(document: PPDocument) -> void

@abstract func undo(document: PPDocument) -> void


## Rect of the sprite whose pixels this command touched, for partial repaint.
## Structural commands return the whole canvas.
func get_dirty_rect(document: PPDocument) -> Rect2i:
	return document.sprite.get_bounds()


## True when the command changed the layer/frame/tag structure, meaning the UI
## must rebuild its lists rather than just repaint the canvas.
func is_structural() -> bool:
	return false


## Gives consecutive same-kind commands a chance to coalesce (e.g. dragging a
## slider). Returning true means `other` was absorbed into `self` and should not
## be pushed onto the stack.
func merge_with(_other: PPCommand) -> bool:
	return false
