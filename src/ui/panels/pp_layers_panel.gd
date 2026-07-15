class_name PPLayersPanel
extends PanelContainer

## The layer stack.
##
## Rows are listed top-layer-first, which is the reverse of how PPSprite stores
## them (bottom-first, matching the compositor and the .ase format). The mapping
## lives only here.

@export var row_scene: PackedScene = null

var app: PPAppState = null
var _document: PPDocument = null
var _syncing: bool = false

@onready var _rows: VBoxContainer = %Rows
@onready var _blend: OptionButton = %BlendOption
@onready var _opacity: HSlider = %OpacitySlider
@onready var _add: Button = %AddButton
@onready var _duplicate: Button = %DuplicateButton
@onready var _merge: Button = %MergeButton
@onready var _up: Button = %UpButton
@onready var _down: Button = %DownButton
@onready var _delete: Button = %DeleteButton


func bind(state: PPAppState) -> void:
	app = state
	app.document_changed.connect(_on_document_changed)

	_blend.clear()
	for i: int in range(PPTypes.BLEND_MODE_NAMES.size()):
		_blend.add_item(PPTypes.BLEND_MODE_NAMES[i], i)

	_blend.item_selected.connect(_on_blend_selected)
	_opacity.value_changed.connect(_on_opacity_changed)
	_add.pressed.connect(_on_add)
	_duplicate.pressed.connect(_on_duplicate)
	_merge.pressed.connect(_on_merge)
	_up.pressed.connect(func() -> void: _move(1))
	_down.pressed.connect(func() -> void: _move(-1))
	_delete.pressed.connect(_on_delete)

	if app.document != null:
		_on_document_changed(app.document)


func _on_document_changed(document: PPDocument) -> void:
	if _document != null:
		if _document.structure_changed.is_connected(_rebuild):
			_document.structure_changed.disconnect(_rebuild)
		if _document.active_cel_changed.is_connected(_rebuild):
			_document.active_cel_changed.disconnect(_rebuild)

	_document = document
	_document.structure_changed.connect(_rebuild)
	_document.active_cel_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	if _document == null:
		return

	for child: Node in _rows.get_children():
		child.queue_free()

	var sprite: PPSprite = _document.sprite
	# Top layer first: the list reads the way the picture stacks.
	for i: int in range(sprite.layer_count() - 1, -1, -1):
		var row: PPLayerRow = row_scene.instantiate() as PPLayerRow
		_rows.add_child(row)
		row.setup(i, sprite.get_layer(i), i == _document.active_layer)
		row.selected.connect(_on_row_selected)
		row.visibility_toggled.connect(_on_visibility_toggled)
		row.lock_toggled.connect(_on_lock_toggled)
		row.layer_renamed.connect(_on_renamed)

	_sync_properties()


func _sync_properties() -> void:
	var layer: PPLayer = _document.get_active_layer()
	if layer == null:
		return

	_syncing = true
	_blend.select(_blend.get_item_index(int(layer.blend_mode)))
	_opacity.value = layer.opacity * 100.0
	_syncing = false

	_delete.disabled = _document.sprite.layer_count() <= 1
	_merge.disabled = _document.active_layer <= 0
	_up.disabled = _document.active_layer >= _document.sprite.layer_count() - 1
	_down.disabled = _document.active_layer <= 0


func _on_row_selected(index: int) -> void:
	_document.active_layer = index


func _on_visibility_toggled(index: int, visible: bool) -> void:
	_document.history.push(
		PPLayerCommands.SetLayerProperty.create(
			_document.sprite, index, &"visible", visible, "Toggle Visibility"
		)
	)


func _on_lock_toggled(index: int, locked: bool) -> void:
	_document.history.push(
		PPLayerCommands.SetLayerProperty.create(
			_document.sprite, index, &"locked", locked, "Toggle Lock"
		)
	)


func _on_renamed(index: int, name: String) -> void:
	_document.history.push(
		PPLayerCommands.SetLayerProperty.create(
			_document.sprite, index, &"name", name, "Rename Layer"
		)
	)


func _on_blend_selected(item_index: int) -> void:
	if _syncing:
		return
	var mode: int = _blend.get_item_id(item_index)
	_document.history.push(
		PPLayerCommands.SetLayerProperty.create(
			_document.sprite,
			_document.active_layer,
			&"blend_mode",
			mode as PPTypes.BlendMode,
			"Blend Mode"
		)
	)


func _on_opacity_changed(value: float) -> void:
	if _syncing:
		return
	# Consecutive SetLayerProperty commands on the same property merge, so
	# dragging the slider is one undo step rather than one per pixel of travel.
	_document.history.push(
		PPLayerCommands.SetLayerProperty.create(
			_document.sprite,
			_document.active_layer,
			&"opacity",
			clampf(value / 100.0, 0.0, 1.0),
			"Layer Opacity"
		)
	)


func _on_add() -> void:
	var sprite: PPSprite = _document.sprite
	var layer: PPLayer = PPLayer.create(
		"Layer %d" % (sprite.layer_count() + 1), sprite.frame_count(), sprite.size
	)
	_document.history.push(
		PPLayerCommands.AddLayer.create(layer, _document.active_layer + 1)
	)


func _on_duplicate() -> void:
	var source: PPLayer = _document.get_active_layer()
	if source == null:
		return
	_document.history.push(
		PPLayerCommands.AddLayer.create(
			source.duplicate_layer(), _document.active_layer + 1
		)
	)


func _on_merge() -> void:
	_document.history.push(
		PPLayerCommands.MergeDown.create(_document.sprite, _document.active_layer)
	)


func _on_delete() -> void:
	_document.history.push(
		PPLayerCommands.RemoveLayer.create(_document.sprite, _document.active_layer)
	)


func _move(direction: int) -> void:
	var target: int = _document.active_layer + direction
	if target < 0 or target >= _document.sprite.layer_count():
		return
	_document.history.push(
		PPLayerCommands.MoveLayer.create(_document.active_layer, target)
	)
