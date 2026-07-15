class_name PPPixelPerfect
extends RefCounted

## Removes the redundant corner pixels that make freehand pixel lines look
## "chunky".
##
## When three consecutive stroke cells form an L -- the outer two being diagonal
## neighbours of each other, and the middle one orthogonally adjacent to both --
## the middle cell adds nothing: the diagonal step alone already connects them.
## Dropping it is what turns a staircase with doubled corners into the clean
## 1px diagonal a pixel artist would have drawn by hand.
##
##     before          after
##     . X X           . . X
##     X X .    -->    . X .
##     X . .           X . .
##
## Stateful and incremental: the filter sees the stroke one cell at a time and
## can retract the cell it emitted last, which is why callers must handle a
## retraction (by un-stamping that dab) rather than assuming append-only output.

var _window: Array[Vector2i] = []


func reset() -> void:
	_window.clear()


## Feeds one cell in. Returns the cell that must be *retracted* (already emitted,
## now known to be a redundant corner), or null if nothing needs undoing.
func push(point: Vector2i) -> Variant:
	if not _window.is_empty() and _window[-1] == point:
		return null

	_window.append(point)
	if _window.size() < 3:
		return null

	var a: Vector2i = _window[0]
	var b: Vector2i = _window[1]
	var c: Vector2i = _window[2]

	if _is_redundant_corner(a, b, c):
		# Drop the corner and keep the two cells that actually carry the line.
		_window = [a, c]
		return b

	_window.remove_at(0)
	return null


static func _is_redundant_corner(a: Vector2i, b: Vector2i, c: Vector2i) -> bool:
	# The outer cells must be diagonal neighbours of each other...
	if absi(c.x - a.x) != 1 or absi(c.y - a.y) != 1:
		return false
	# ...and the middle cell orthogonally adjacent to both.
	if absi(b.x - a.x) + absi(b.y - a.y) != 1:
		return false
	if absi(c.x - b.x) + absi(c.y - b.y) != 1:
		return false
	return true
