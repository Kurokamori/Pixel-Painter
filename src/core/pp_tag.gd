class_name PPTag
extends Resource

## A named, inclusive range of frames with its own playback direction -- the
## equivalent of an Aseprite tag ("walk", "idle", ...).

@export var name: String = "Tag"
@export var from_frame: int = 0
@export var to_frame: int = 0
@export var direction: PPTypes.AnimationDirection = PPTypes.AnimationDirection.FORWARD
@export var color: Color = Color(0.35, 0.72, 1.0)

## 0 means "loop forever"; any other value plays the tag that many times.
@export var repeat: int = 0


static func create(tag_name: String, from_index: int, to_index: int) -> PPTag:
	var tag: PPTag = PPTag.new()
	tag.name = tag_name
	tag.from_frame = mini(from_index, to_index)
	tag.to_frame = maxi(from_index, to_index)
	return tag


func contains(frame_index: int) -> bool:
	return frame_index >= from_frame and frame_index <= to_frame


func frame_count() -> int:
	return to_frame - from_frame + 1


## Remaps the tag when frames are inserted at `at`. Returns false when the tag
## no longer describes a valid range and should be dropped.
func shift_for_insert(at: int, count: int) -> bool:
	if at <= from_frame:
		from_frame += count
		to_frame += count
	elif at <= to_frame:
		to_frame += count
	return true


## Remaps the tag when the frame at `at` is removed. Returns false when the tag
## has collapsed to nothing and should be dropped.
func shift_for_remove(at: int) -> bool:
	if at < from_frame:
		from_frame -= 1
		to_frame -= 1
	elif at <= to_frame:
		to_frame -= 1
	return to_frame >= from_frame


func duplicate_tag() -> PPTag:
	var copy: PPTag = PPTag.new()
	copy.name = name
	copy.from_frame = from_frame
	copy.to_frame = to_frame
	copy.direction = direction
	copy.color = color
	copy.repeat = repeat
	return copy
