class_name PPFrame
extends Resource

## Per-frame metadata. Pixels live in each layer's cel for this frame index.

@export var duration_ms: int = PPTypes.DEFAULT_FRAME_DURATION_MS


static func create(duration: int = PPTypes.DEFAULT_FRAME_DURATION_MS) -> PPFrame:
	var frame: PPFrame = PPFrame.new()
	frame.duration_ms = maxi(1, duration)
	return frame


func duplicate_frame() -> PPFrame:
	return PPFrame.create(duration_ms)
