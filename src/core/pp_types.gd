@abstract
class_name PPTypes
extends RefCounted

## Shared enumerations and constants for the Pixel Painter document model.
## This class is never instantiated; it exists purely as a namespace.

enum BlendMode {
	NORMAL,
	DARKEN,
	MULTIPLY,
	COLOR_BURN,
	LIGHTEN,
	SCREEN,
	COLOR_DODGE,
	ADDITION,
	OVERLAY,
	SOFT_LIGHT,
	HARD_LIGHT,
	DIFFERENCE,
	EXCLUSION,
	SUBTRACT,
	DIVIDE,
	HUE,
	SATURATION,
	COLOR,
	LUMINOSITY,
}

enum AnimationDirection {
	FORWARD,
	REVERSE,
	PING_PONG,
	PING_PONG_REVERSE,
}

enum SelectionOp {
	REPLACE,
	ADD,
	SUBTRACT,
	INTERSECT,
}

enum SymmetryMode {
	NONE,
	HORIZONTAL,
	VERTICAL,
	BOTH,
}

enum BrushShape {
	CIRCLE,
	SQUARE,
	DIAMOND,
}

## How a tool maps stylus pressure onto its output.
enum PressureTarget {
	NONE,
	SIZE,
	OPACITY,
	SIZE_AND_OPACITY,
}

const BLEND_MODE_NAMES: Array[String] = [
	"Normal",
	"Darken",
	"Multiply",
	"Color Burn",
	"Lighten",
	"Screen",
	"Color Dodge",
	"Addition",
	"Overlay",
	"Soft Light",
	"Hard Light",
	"Difference",
	"Exclusion",
	"Subtract",
	"Divide",
	"Hue",
	"Saturation",
	"Color",
	"Luminosity",
]

## Aseprite's on-disk blend mode identifiers, indexed by our BlendMode.
##
## Aseprite orders its blend modes differently from us (it groups by darken /
## lighten families), so this is a genuine remap and not the identity. Getting it
## wrong silently corrupts layer blending on .ase round-trips.
const ASE_BLEND_IDS: Array[int] = [
	0,   # NORMAL
	4,   # DARKEN
	1,   # MULTIPLY
	7,   # COLOR_BURN
	5,   # LIGHTEN
	2,   # SCREEN
	6,   # COLOR_DODGE
	16,  # ADDITION
	3,   # OVERLAY
	9,   # SOFT_LIGHT
	8,   # HARD_LIGHT
	10,  # DIFFERENCE
	11,  # EXCLUSION
	17,  # SUBTRACT
	18,  # DIVIDE
	12,  # HUE
	13,  # SATURATION
	14,  # COLOR
	15,  # LUMINOSITY
]

## Aseprite's 128-byte header, after the fields we actually read, has this many
## bytes of pixel-ratio, grid and reserved padding left to skip.
const ASE_HEADER_TAIL: int = 94

const MAX_SPRITE_SIZE: int = 4096
const MIN_SPRITE_SIZE: int = 1
const DEFAULT_FRAME_DURATION_MS: int = 100

## Bytes-per-pixel of the working surface format (always Image.FORMAT_RGBA8).
const BPP: int = 4


static func blend_mode_name(mode: BlendMode) -> String:
	var index: int = int(mode)
	if index < 0 or index >= BLEND_MODE_NAMES.size():
		return "Normal"
	return BLEND_MODE_NAMES[index]


## Our BlendMode -> Aseprite's on-disk id.
static func to_ase_blend_id(mode: BlendMode) -> int:
	var index: int = int(mode)
	if index < 0 or index >= ASE_BLEND_IDS.size():
		return 0
	return ASE_BLEND_IDS[index]


## Aseprite's on-disk id -> our BlendMode. Unknown ids degrade to Normal.
static func from_ase_blend_id(ase_id: int) -> BlendMode:
	var index: int = ASE_BLEND_IDS.find(ase_id)
	if index < 0:
		return BlendMode.NORMAL
	return index as BlendMode
