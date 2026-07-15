class_name PPPointer
extends RefCounted

## One pointer sample, normalised across mouse, pen tablet and touch.
##
## Godot reports stylus data on both InputEventMouseMotion (Wacom and friends on
## desktop) and InputEventScreenDrag (Apple Pencil on iOS), with identical
## `pressure` / `tilt` / `pen_inverted` fields -- so the canvas can flatten every
## input device into this one struct and no tool needs to know the difference.

## Canvas position in pixel units, with sub-pixel precision retained.
var position: Vector2 = Vector2.ZERO

## 0.0 - 1.0. Mice and fingers report 1.0 (a full-pressure press).
var pressure: float = 1.0

## Stylus tilt in x/y, each -1.0 - 1.0. Zero for non-stylus input.
var tilt: Vector2 = Vector2.ZERO

## True when the stylus is flipped to its eraser end.
var inverted: bool = false

## True when this sample came from a finger rather than a stylus or mouse. The
## canvas uses it for palm rejection and to route finger drags to pan/zoom while
## a pen is in use.
var is_touch: bool = false

## Which mouse button initiated the gesture (right button paints the secondary
## colour, mirroring every other pixel editor).
var secondary: bool = false

var shift: bool = false
var control: bool = false
var alt: bool = false


func get_cell() -> Vector2i:
	return Vector2i(floori(position.x), floori(position.y))


func duplicate_pointer() -> PPPointer:
	var copy: PPPointer = PPPointer.new()
	copy.position = position
	copy.pressure = pressure
	copy.tilt = tilt
	copy.inverted = inverted
	copy.is_touch = is_touch
	copy.secondary = secondary
	copy.shift = shift
	copy.control = control
	copy.alt = alt
	return copy
