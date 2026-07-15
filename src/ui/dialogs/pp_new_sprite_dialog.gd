class_name PPNewSpriteDialog
extends ConfirmationDialog

## Asks for a canvas size and a starting palette.

signal create_requested(size: Vector2i, palette: PPPalette)

## Label, then width and height. Chosen to cover the sizes pixel artists
## actually work at rather than to be exhaustive.
const PRESETS: Array[String] = [
	"Custom",
	"16 × 16  (icon)",
	"32 × 32  (sprite)",
	"64 × 64  (character)",
	"128 × 128  (portrait)",
	"320 × 180  (16:9 scene)",
	"160 × 144  (Game Boy)",
	"256 × 240  (NES)",
]

const PRESET_SIZES: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(16, 16),
	Vector2i(32, 32),
	Vector2i(64, 64),
	Vector2i(128, 128),
	Vector2i(320, 180),
	Vector2i(160, 144),
	Vector2i(256, 240),
]

var _syncing: bool = false

@onready var _preset: OptionButton = %PresetOption
@onready var _width: SpinBox = %WidthSpin
@onready var _height: SpinBox = %HeightSpin
@onready var _palette: OptionButton = %PaletteOption


func _ready() -> void:
	for i: int in range(PRESETS.size()):
		_preset.add_item(PRESETS[i], i)
	_preset.select(3)

	var names: PackedStringArray = PPDefaultPalettes.get_names()
	for i: int in range(names.size()):
		_palette.add_item(names[i], i)
	_palette.select(0)

	_preset.item_selected.connect(_on_preset_selected)
	_width.value_changed.connect(_on_size_changed)
	_height.value_changed.connect(_on_size_changed)
	confirmed.connect(_on_confirmed)


func _on_preset_selected(index: int) -> void:
	var id: int = _preset.get_item_id(index)
	if id <= 0 or id >= PRESET_SIZES.size():
		return
	_syncing = true
	_width.value = PRESET_SIZES[id].x
	_height.value = PRESET_SIZES[id].y
	_syncing = false


## Typing a size that no longer matches the chosen preset drops the preset back
## to Custom, rather than leaving a label that lies about the numbers below it.
func _on_size_changed(_value: float) -> void:
	if _syncing:
		return
	var current: Vector2i = Vector2i(int(_width.value), int(_height.value))
	for i: int in range(1, PRESET_SIZES.size()):
		if PRESET_SIZES[i] == current:
			_preset.select(_preset.get_item_index(i))
			return
	_preset.select(0)


func _on_confirmed() -> void:
	var size: Vector2i = Vector2i(int(_width.value), int(_height.value))
	size.x = clampi(size.x, PPTypes.MIN_SPRITE_SIZE, PPTypes.MAX_SPRITE_SIZE)
	size.y = clampi(size.y, PPTypes.MIN_SPRITE_SIZE, PPTypes.MAX_SPRITE_SIZE)

	var names: PackedStringArray = PPDefaultPalettes.get_names()
	var selected: int = _palette.get_item_id(_palette.selected)
	var palette: PPPalette = PPDefaultPalettes.get_default()
	if selected >= 0 and selected < names.size():
		palette = PPDefaultPalettes.get_palette(names[selected])

	create_requested.emit(size, palette)
