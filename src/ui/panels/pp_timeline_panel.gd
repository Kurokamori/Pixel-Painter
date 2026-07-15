class_name PPTimelinePanel
extends PanelContainer

## Frame strip and playback transport.
##
## Thumbnails are regenerated only when the sprite's structure or pixels actually
## change, and are downscaled once into a small texture -- redrawing 60 full
## composites per frame of playback would cost more than the playback itself.

const THUMBNAIL_MAX: int = 40

@export var cell_scene: PackedScene = null

var app: PPAppState = null
var _document: PPDocument = null
var _prefs: PPSettings = null
var _syncing: bool = false
var _thumbnails_dirty: bool = true

@onready var _frames: HBoxContainer = %Frames
@onready var _first: Button = %FirstButton
@onready var _prev: Button = %PrevButton
@onready var _play: Button = %PlayButton
@onready var _next: Button = %NextButton
@onready var _last: Button = %LastButton
@onready var _loop: Button = %LoopButton
@onready var _onion: Button = %OnionButton
@onready var _duration: SpinBox = %DurationSpin
@onready var _add_frame: Button = %AddFrameButton
@onready var _duplicate_frame: Button = %DuplicateFrameButton
@onready var _link_frame: Button = %LinkFrameButton
@onready var _unlink_frame: Button = %UnlinkFrameButton
@onready var _delete_frame: Button = %DeleteFrameButton


func bind(state: PPAppState) -> void:
	app = state
	_prefs = PPSettings.get_instance()

	app.document_changed.connect(_on_document_changed)
	app.playback_changed.connect(_on_playback_changed)

	_first.pressed.connect(func() -> void: _goto(0))
	_prev.pressed.connect(func() -> void: _step(-1))
	_next.pressed.connect(func() -> void: _step(1))
	_last.pressed.connect(
		func() -> void: _goto(_document.sprite.frame_count() - 1)
	)
	_play.toggled.connect(func(on: bool) -> void: app.set_playing(on))
	_loop.toggled.connect(func(on: bool) -> void: app.loop_playback = on)
	_onion.toggled.connect(_on_onion_toggled)
	_duration.value_changed.connect(_on_duration_changed)

	_add_frame.pressed.connect(_on_add_frame)
	_duplicate_frame.pressed.connect(_on_duplicate_frame)
	_link_frame.pressed.connect(_on_link_frame)
	_unlink_frame.pressed.connect(_on_unlink_frame)
	_delete_frame.pressed.connect(_on_delete_frame)

	_onion.set_pressed_no_signal(_prefs.onion_enabled)

	if app.document != null:
		_on_document_changed(app.document)


func _on_document_changed(document: PPDocument) -> void:
	if _document != null:
		if _document.structure_changed.is_connected(_on_structure_changed):
			_document.structure_changed.disconnect(_on_structure_changed)
		if _document.active_cel_changed.is_connected(_refresh_selection):
			_document.active_cel_changed.disconnect(_refresh_selection)
		if _document.canvas_changed.is_connected(_on_canvas_changed):
			_document.canvas_changed.disconnect(_on_canvas_changed)

	_document = document
	_document.structure_changed.connect(_on_structure_changed)
	_document.active_cel_changed.connect(_refresh_selection)
	_document.canvas_changed.connect(_on_canvas_changed)

	_thumbnails_dirty = true
	_rebuild()


func _on_structure_changed() -> void:
	_thumbnails_dirty = true
	_rebuild()


func _on_canvas_changed(_rect: Rect2i) -> void:
	# Pixels moved, so this frame's thumbnail is stale -- but rebuilding the
	# whole strip on every dab of a stroke would be absurd. Mark it and let the
	# next structural change or frame switch pick it up.
	_thumbnails_dirty = true


func _rebuild() -> void:
	if _document == null or cell_scene == null:
		return

	for child: Node in _frames.get_children():
		child.queue_free()

	var sprite: PPSprite = _document.sprite
	var layer: PPLayer = _document.get_active_layer()

	for i: int in range(sprite.frame_count()):
		var cell: PPFrameCell = cell_scene.instantiate() as PPFrameCell
		_frames.add_child(cell)
		cell.setup(
			i,
			sprite.get_frame(i).duration_ms,
			_thumbnail(i),
			layer != null and layer.is_cel_linked(i),
			i == _document.active_frame
		)
		cell.chosen.connect(_goto)

	_thumbnails_dirty = false
	_sync_controls()


func _thumbnail(frame_index: int) -> Texture2D:
	var image: Image = PPCompositor.flatten_frame(_document.sprite, frame_index)

	var size: Vector2i = _document.sprite.size
	var longest: int = maxi(size.x, size.y)
	if longest > THUMBNAIL_MAX:
		var scale: float = float(THUMBNAIL_MAX) / float(longest)
		image.resize(
			maxi(1, int(size.x * scale)),
			maxi(1, int(size.y * scale)),
			Image.INTERPOLATE_NEAREST
		)

	return ImageTexture.create_from_image(image)


func _refresh_selection() -> void:
	if _thumbnails_dirty:
		_rebuild()
		return

	for child: Node in _frames.get_children():
		var cell: PPFrameCell = child as PPFrameCell
		if cell != null:
			cell.set_pressed_no_signal(cell.frame_index == _document.active_frame)

	_sync_controls()


func _sync_controls() -> void:
	if _document == null:
		return

	_syncing = true
	_duration.value = _document.sprite.get_frame(_document.active_frame).duration_ms
	_syncing = false

	_delete_frame.disabled = _document.sprite.frame_count() <= 1

	var layer: PPLayer = _document.get_active_layer()
	_unlink_frame.disabled = (
		layer == null or not layer.is_cel_linked(_document.active_frame)
	)


func _on_playback_changed(playing: bool) -> void:
	_play.set_pressed_no_signal(playing)
	_play.text = "⏸" if playing else "▶"


func _on_onion_toggled(on: bool) -> void:
	_prefs.onion_enabled = on
	_prefs.save_settings()
	# The canvas rebuilds its onion textures from the settings, so nudging the
	# document is enough to make it repaint.
	_document.refresh_composite()


func _goto(frame_index: int) -> void:
	_document.active_frame = frame_index


func _step(delta: int) -> void:
	var count: int = _document.sprite.frame_count()
	_document.active_frame = posmod(_document.active_frame + delta, count)


func _on_duration_changed(value: float) -> void:
	if _syncing:
		return
	_document.history.push(
		PPFrameCommands.SetFrameDuration.create(
			_document.sprite, _document.active_frame, int(value)
		)
	)


func _on_add_frame() -> void:
	_document.history.push(
		PPFrameCommands.InsertFrame.create(
			_document.sprite, _document.active_frame + 1, -1, false, "Add Frame"
		)
	)


func _on_duplicate_frame() -> void:
	_document.history.push(
		PPFrameCommands.InsertFrame.create(
			_document.sprite,
			_document.active_frame + 1,
			_document.active_frame,
			false,
			"Duplicate Frame"
		)
	)


func _on_link_frame() -> void:
	_document.history.push(
		PPFrameCommands.InsertFrame.create(
			_document.sprite,
			_document.active_frame + 1,
			_document.active_frame,
			true,
			"Link Frame"
		)
	)


func _on_unlink_frame() -> void:
	_document.history.push(
		PPFrameCommands.SetCel.create_unlink(
			_document.sprite, _document.active_layer, _document.active_frame
		)
	)


func _on_delete_frame() -> void:
	_document.history.push(
		PPFrameCommands.RemoveFrame.create(_document.sprite, _document.active_frame)
	)
