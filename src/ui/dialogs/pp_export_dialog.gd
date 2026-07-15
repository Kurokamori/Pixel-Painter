class_name PPExportDialog
extends ConfirmationDialog

## Picks an export format and its options. The dialog gathers intent only; the
## app root then asks for a destination and performs the export.

signal export_requested(config: PPExportDialog.Config)

enum Format {
	PNG_FRAME,
	PNG_FRAMES,
	SPRITESHEET,
	GIF,
}


class Config:
	extends RefCounted

	var format: Format = Format.PNG_FRAME
	var scale: int = 1
	var sheet: PPExportIO.SheetOptions = PPExportIO.SheetOptions.new()

	## The extension the save dialog should default to.
	func get_extension() -> String:
		return "gif" if format == Format.GIF else "png"


var _document: PPDocument = null

@onready var _format: OptionButton = %FormatOption
@onready var _scale: SpinBox = %ScaleSpin
@onready var _layout_row: HBoxContainer = %LayoutRow
@onready var _layout: OptionButton = %LayoutOption
@onready var _columns_row: HBoxContainer = %ColumnsRow
@onready var _columns: SpinBox = %ColumnsSpin
@onready var _metadata_row: HBoxContainer = %MetadataRow
@onready var _metadata: CheckButton = %MetadataCheck
@onready var _summary: Label = %SummaryLabel


func _ready() -> void:
	_format.add_item("PNG — current frame", int(Format.PNG_FRAME))
	_format.add_item("PNG — one file per frame", int(Format.PNG_FRAMES))
	_format.add_item("PNG — sprite sheet", int(Format.SPRITESHEET))
	_format.add_item("GIF — animation", int(Format.GIF))
	_format.select(0)

	_layout.add_item("Horizontal strip", int(PPExportIO.SheetLayout.HORIZONTAL))
	_layout.add_item("Vertical strip", int(PPExportIO.SheetLayout.VERTICAL))
	_layout.add_item("Grid", int(PPExportIO.SheetLayout.GRID))
	_layout.select(0)

	_format.item_selected.connect(func(_i: int) -> void: _refresh())
	_layout.item_selected.connect(func(_i: int) -> void: _refresh())
	_scale.value_changed.connect(func(_v: float) -> void: _refresh())
	_columns.value_changed.connect(func(_v: float) -> void: _refresh())
	confirmed.connect(_on_confirmed)

	_refresh()


func open_for(document: PPDocument) -> void:
	_document = document
	_refresh()
	popup_centered()


func _current_format() -> Format:
	return _format.get_item_id(_format.selected) as Format


func _current_layout() -> PPExportIO.SheetLayout:
	return _layout.get_item_id(_layout.selected) as PPExportIO.SheetLayout


func _refresh() -> void:
	var format: Format = _current_format()
	var is_sheet: bool = format == Format.SPRITESHEET

	_layout_row.visible = is_sheet
	_metadata_row.visible = is_sheet
	_columns_row.visible = (
		is_sheet and _current_layout() == PPExportIO.SheetLayout.GRID
	)

	_summary.text = _describe(format)


## Tells the user exactly what they are about to get -- dimensions and file
## count -- because "sprite sheet" alone does not answer either question.
func _describe(format: Format) -> String:
	if _document == null:
		return ""

	var size: Vector2i = _document.sprite.size
	var frames: int = _document.sprite.frame_count()
	var scale: int = int(_scale.value)
	var scaled: Vector2i = size * scale

	match format:
		Format.PNG_FRAME:
			return "One %d × %d PNG of the current frame." % [scaled.x, scaled.y]
		Format.PNG_FRAMES:
			return "%d PNGs, each %d × %d." % [frames, scaled.x, scaled.y]
		Format.SPRITESHEET:
			var grid: Vector2i = _sheet_grid(frames)
			return "One %d × %d sheet, %d × %d frames." % [
				grid.x * scaled.x, grid.y * scaled.y, grid.x, grid.y
			]
		Format.GIF:
			var duration: float = float(_document.sprite.total_duration_ms()) / 1000.0
			return "One animated GIF, %d frames, %.1fs per loop." % [frames, duration]
	return ""


func _sheet_grid(frames: int) -> Vector2i:
	match _current_layout():
		PPExportIO.SheetLayout.HORIZONTAL:
			return Vector2i(frames, 1)
		PPExportIO.SheetLayout.VERTICAL:
			return Vector2i(1, frames)
	var columns: int = maxi(1, int(_columns.value))
	return Vector2i(columns, int(ceil(float(frames) / float(columns))))


func _on_confirmed() -> void:
	var config: Config = Config.new()
	config.format = _current_format()
	config.scale = int(_scale.value)
	config.sheet.layout = _current_layout()
	config.sheet.columns = int(_columns.value)
	config.sheet.write_metadata = _metadata.button_pressed
	config.sheet.scale = config.scale
	export_requested.emit(config)
