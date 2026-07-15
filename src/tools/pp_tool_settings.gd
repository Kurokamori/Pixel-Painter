class_name PPToolSettings
extends RefCounted

## Every knob the tool options bar exposes, in one place.
##
## Shared by reference between the app state, the options UI and the active
## tool, so a change in the UI is visible to the very next stroke with no
## plumbing in between.

signal changed()

# --- Colour ---
var primary_color: Color = Color(0.05, 0.05, 0.08, 1.0)
var secondary_color: Color = Color(1.0, 1.0, 1.0, 1.0)

# --- Brush ---
var brush_shape: PPTypes.BrushShape = PPTypes.BrushShape.CIRCLE
var brush_size: int = 1
var opacity: float = 1.0

## Removes redundant corner cells from freehand strokes. See PPPixelPerfect.
var pixel_perfect: bool = true

## Paints RGB only where the cel is already opaque -- Aseprite's "lock alpha".
var lock_alpha: bool = false

# --- Stylus ---
var pressure_target: PPTypes.PressureTarget = PPTypes.PressureTarget.SIZE
## Pressure 0 maps to this fraction of the nominal brush size, never to zero:
## a stylus that reports 0.0 on first contact should still make a mark.
var min_pressure_scale: float = 0.25

# --- Fill / sampling ---
var tolerance: int = 0
var contiguous: bool = true
## Sample the flattened frame rather than just the active layer (bucket, wand,
## eyedropper). Aseprite spells this "Sample: All Layers".
var sample_all_layers: bool = false

# --- Shapes ---
var shape_filled: bool = false
var shape_from_center: bool = false

# --- Selection ---
var selection_op: PPTypes.SelectionOp = PPTypes.SelectionOp.REPLACE

# --- Symmetry ---
var symmetry: PPTypes.SymmetryMode = PPTypes.SymmetryMode.NONE


func notify_changed() -> void:
	changed.emit()


## Swaps the two active colours (X in Aseprite).
func swap_colors() -> void:
	var held: Color = primary_color
	primary_color = secondary_color
	secondary_color = held
	changed.emit()


func set_primary(color: Color) -> void:
	if primary_color == color:
		return
	primary_color = color
	changed.emit()


func set_secondary(color: Color) -> void:
	if secondary_color == color:
		return
	secondary_color = color
	changed.emit()


func set_brush_size(value: int) -> void:
	var clamped: int = clampi(value, 1, 64)
	if brush_size == clamped:
		return
	brush_size = clamped
	changed.emit()


## Effective dab size for a given stylus pressure.
func size_for_pressure(pressure: float) -> int:
	if (
		pressure_target != PPTypes.PressureTarget.SIZE
		and pressure_target != PPTypes.PressureTarget.SIZE_AND_OPACITY
	):
		return brush_size
	var scale: float = lerpf(min_pressure_scale, 1.0, clampf(pressure, 0.0, 1.0))
	return maxi(1, int(round(float(brush_size) * scale)))


## Effective dab alpha (0-255) for a given stylus pressure.
func alpha_for_pressure(pressure: float) -> int:
	var value: float = opacity
	if (
		pressure_target == PPTypes.PressureTarget.OPACITY
		or pressure_target == PPTypes.PressureTarget.SIZE_AND_OPACITY
	):
		value *= clampf(pressure, 0.0, 1.0)
	return clampi(int(round(value * 255.0)), 0, 255)
