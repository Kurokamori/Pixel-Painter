class_name PPFrameCell
extends Button

## One frame in the timeline: index, a live thumbnail, its duration, and a badge
## when the active layer's cel is linked to another frame's.

signal chosen(frame_index: int)

var frame_index: int = 0


func _ready() -> void:
	pressed.connect(func() -> void: chosen.emit(frame_index))


func setup(
	index: int, duration_ms: int, thumbnail: Texture2D, linked: bool, active: bool
) -> void:
	frame_index = index

	var index_label: Label = get_node("%IndexLabel")
	var duration_label: Label = get_node("%DurationLabel")
	var thumb: TextureRect = get_node("%Thumbnail")
	var badge: Label = get_node("%LinkBadge")

	index_label.text = str(index + 1)
	duration_label.text = "%dms" % duration_ms
	thumb.texture = thumbnail
	# Thumbnails are tiny sprites; anything but nearest turns them to mush.
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	badge.visible = linked

	set_pressed_no_signal(active)
	tooltip_text = "Frame %d — %dms" % [index + 1, duration_ms]
