class_name PPResizeDialog
extends ConfirmationDialog

## Two operations behind one dialog, because the user thinks of them together
## and gets them confused apart:
##
##   Resize Canvas  changes the canvas, leaves the art at its original scale.
##   Scale Sprite   resamples the art itself, nearest-neighbour.

signal resize_requested(size: Vector2i, offset: Vector2i)
signal scale_requested(size: Vector2i)

## Named ResizeMode, not Mode: Window already defines a `Mode` enum, and
## shadowing it makes every use of this one a type error.
enum ResizeMode {
	CANVAS,
	SCALE,
}

const ANCHORS: Array[String] = [
	"Top Left", "Top", "Top Right",
	"Left", "Centre", "Right",
	"Bottom Left", "Bottom", "Bottom Right",
]

var _mode: ResizeMode = ResizeMode.CANVAS
var _original: Vector2i = Vector2i(64, 64)
var _syncing: bool = false

@onready var _mode_label: Label = %ModeLabel
@onready var _width: SpinBox = %WidthSpin
@onready var _height: SpinBox = %HeightSpin
@onready var _ratio: CheckButton = %RatioCheck
@onready var _anchor_row: HBoxContainer = %AnchorRow
@onready var _anchor: OptionButton = %AnchorOption
@onready var _hint: Label = %Hint


func _ready() -> void:
	for i: int in range(ANCHORS.size()):
		_anchor.add_item(ANCHORS[i], i)
	_anchor.select(4)

	_width.value_changed.connect(_on_width_changed)
	_height.value_changed.connect(_on_height_changed)
	confirmed.connect(_on_confirmed)


func open_for(document: PPDocument, mode: ResizeMode) -> void:
	_mode = mode
	_original = document.sprite.size

	_syncing = true
	_width.value = _original.x
	_height.value = _original.y
	_syncing = false

	if mode == ResizeMode.CANVAS:
		title = "Resize Canvas"
		_mode_label.text = "Resize Canvas"
		_hint.text = (
			"Changes the canvas only. Artwork keeps its size and is anchored "
			+ "where you choose; anything outside the new bounds is cropped."
		)
		_anchor_row.visible = true
		_ratio.button_pressed = false
	else:
		title = "Scale Sprite"
		_mode_label.text = "Scale Sprite"
		_hint.text = (
			"Resamples the artwork with nearest-neighbour, so pixels stay hard. "
			+ "Whole-number multiples give the cleanest result."
		)
		_anchor_row.visible = false
		_ratio.button_pressed = true

	popup_centered()


func _on_width_changed(value: float) -> void:
	if _syncing or not _ratio.button_pressed or _original.x <= 0:
		return
	_syncing = true
	_height.value = round(value * float(_original.y) / float(_original.x))
	_syncing = false


func _on_height_changed(value: float) -> void:
	if _syncing or not _ratio.button_pressed or _original.y <= 0:
		return
	_syncing = true
	_width.value = round(value * float(_original.x) / float(_original.y))
	_syncing = false


func _on_confirmed() -> void:
	var size: Vector2i = Vector2i(int(_width.value), int(_height.value))
	size.x = clampi(size.x, PPTypes.MIN_SPRITE_SIZE, PPTypes.MAX_SPRITE_SIZE)
	size.y = clampi(size.y, PPTypes.MIN_SPRITE_SIZE, PPTypes.MAX_SPRITE_SIZE)

	if _mode == ResizeMode.SCALE:
		scale_requested.emit(size)
		return

	resize_requested.emit(size, _compute_offset(size))


## Turns the 3x3 anchor choice into the offset at which the old canvas lands
## inside the new one.
func _compute_offset(size: Vector2i) -> Vector2i:
	var choice: int = _anchor.get_item_id(_anchor.selected)
	var column: int = choice % 3
	var row: int = choice / 3

	var delta: Vector2i = size - _original
	var offset: Vector2i = Vector2i.ZERO

	match column:
		1:
			offset.x = delta.x / 2
		2:
			offset.x = delta.x
	match row:
		1:
			offset.y = delta.y / 2
		2:
			offset.y = delta.y

	return offset
