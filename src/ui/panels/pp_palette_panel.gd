class_name PPPalettePanel
extends PanelContainer

## The swatch rack for the sprite's palette.
##
## Swatches are instances of palette_swatch.tscn rather than nodes built in code
## -- the palette is data, so its rows have to be dynamic, but each *item* is
## still an editable scene.

signal load_palette_requested()
signal save_palette_requested()

@export var swatch_scene: PackedScene = null

var app: PPAppState = null

var _document: PPDocument = null
var _selected: int = -1

@onready var _grid: GridContainer = %Grid
@onready var _palette_option: OptionButton = %PaletteOption
@onready var _load: Button = %LoadButton
@onready var _save: Button = %SaveButton
@onready var _add: Button = %AddButton
@onready var _remove: Button = %RemoveButton
@onready var _sort: Button = %SortButton


func bind(state: PPAppState) -> void:
	app = state
	app.document_changed.connect(_on_document_changed)

	_palette_option.clear()
	_palette_option.add_item("Palette…", -1)
	var names: PackedStringArray = PPDefaultPalettes.get_names()
	for i: int in range(names.size()):
		_palette_option.add_item(names[i], i)

	_palette_option.item_selected.connect(_on_builtin_selected)
	_load.pressed.connect(func() -> void: load_palette_requested.emit())
	_save.pressed.connect(func() -> void: save_palette_requested.emit())
	_add.pressed.connect(_on_add)
	_remove.pressed.connect(_on_remove)
	_sort.pressed.connect(_on_sort)

	if app.document != null:
		_on_document_changed(app.document)


func _on_document_changed(document: PPDocument) -> void:
	if _document != null and _document.structure_changed.is_connected(_rebuild):
		_document.structure_changed.disconnect(_rebuild)

	_document = document
	_document.structure_changed.connect(_rebuild)
	if not _document.sprite.palette.palette_changed.is_connected(_rebuild):
		_document.sprite.palette.palette_changed.connect(_rebuild)

	_selected = -1
	_rebuild()


func _rebuild() -> void:
	if _document == null:
		return

	for child: Node in _grid.get_children():
		child.queue_free()

	var palette: PPPalette = _document.sprite.palette
	for i: int in range(palette.size()):
		var swatch: PPPaletteSwatch = swatch_scene.instantiate() as PPPaletteSwatch
		_grid.add_child(swatch)
		swatch.setup(i, palette.get_color(i), palette.get_color_name(i))
		swatch.set_selected(i == _selected)
		swatch.picked.connect(_on_swatch_picked)


func _on_swatch_picked(index: int, secondary: bool) -> void:
	var color: Color = _document.sprite.palette.get_color(index)
	if secondary:
		app.settings.set_secondary(color)
	else:
		app.settings.set_primary(color)

	_selected = index
	for child: Node in _grid.get_children():
		var swatch: PPPaletteSwatch = child as PPPaletteSwatch
		if swatch != null:
			swatch.set_selected(swatch.index == index)


func _on_builtin_selected(item_index: int) -> void:
	var id: int = _palette_option.get_item_id(item_index)
	if id < 0:
		return

	var names: PackedStringArray = PPDefaultPalettes.get_names()
	if id >= names.size():
		return

	var palette: PPPalette = PPDefaultPalettes.get_palette(names[id])
	if palette == null:
		return

	apply_palette(palette)
	# Snap back to the prompt so the same palette can be re-picked to reset it.
	_palette_option.select(0)


## Replaces the sprite's palette as one undoable step.
func apply_palette(palette: PPPalette) -> void:
	_document.history.push(
		PPPaletteCommand.create(
			_document.sprite.palette, palette, "Load Palette: %s" % palette.name
		)
	)
	_selected = -1
	_rebuild()


func get_palette() -> PPPalette:
	if _document == null:
		return null
	return _document.sprite.palette


func _on_add() -> void:
	var palette: PPPalette = _document.sprite.palette
	var updated: PPPalette = palette.duplicate_palette()
	updated.add_color(app.settings.primary_color)
	_document.history.push(
		PPPaletteCommand.create(palette, updated, "Add Swatch")
	)
	_rebuild()


func _on_remove() -> void:
	if _selected < 0:
		return
	var palette: PPPalette = _document.sprite.palette
	var updated: PPPalette = palette.duplicate_palette()
	updated.remove_color(_selected)
	_document.history.push(
		PPPaletteCommand.create(palette, updated, "Remove Swatch")
	)
	_selected = -1
	_rebuild()


func _on_sort() -> void:
	var palette: PPPalette = _document.sprite.palette
	var updated: PPPalette = palette.duplicate_palette()
	updated.sort_by_luminance()
	_document.history.push(
		PPPaletteCommand.create(palette, updated, "Sort Palette")
	)
	_rebuild()
