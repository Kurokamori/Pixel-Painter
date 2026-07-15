class_name PPCanvasView
extends Control

## The drawing surface: viewport transform, all the overlays, and every pointer
## event in the app.
##
## ## Input routing
##
## Godot reports stylus data identically on desktop and iOS -- pressure, tilt and
## pen_inverted live on InputEventMouseMotion (Wacom) *and* on
## InputEventScreenDrag (Apple Pencil) -- so both collapse into one PPPointer and
## the tools never learn which device drew the stroke.
##
## Touch is the awkward one, because Godot exposes no "this came from a stylus"
## flag on iOS. The rule used here:
##
##   * Two or more contacts always pan/zoom, and cancel any stroke in progress.
##   * A stylus is *detected* the first time any event reports tilt or an
##     inverted (eraser-end) barrel. From then on, single-finger drags pan and
##     the stylus draws -- which is what an artist resting a hand on an iPad
##     expects.
##   * Until a stylus has ever been seen, a single finger draws, so a
##     finger-only user is not locked out of their own canvas.
##   * While a stylus is in contact, new touch contacts are ignored outright.
##     That is palm rejection, and it is why you can rest your hand while drawing.

signal pointer_moved(cell: Vector2i)
signal zoom_changed(zoom: float)

const MIN_ZOOM: float = 0.25
const MAX_ZOOM: float = 64.0
const ZOOM_STEP: float = 1.15
## Below this, a 1px grid is denser than the pixels it is meant to separate.
const PIXEL_GRID_MIN_ZOOM: float = 6.0

var app: PPAppState = null

var zoom: float = 8.0
var origin: Vector2 = Vector2.ZERO

var _document: PPDocument = null
var _prefs: PPSettings = null

var _checker: ImageTexture = null
var _checker_key: String = ""

## Onion skin textures, rebuilt only when the frame or the settings change.
var _onion_before: Array[ImageTexture] = []
var _onion_after: Array[ImageTexture] = []
var _onion_key: String = ""

var _selection_outline: PackedVector2Array = PackedVector2Array()
var _selection_dirty: bool = true

var _hover_cell: Vector2i = Vector2i.ZERO
var _hover_valid: bool = false

# --- Pointer state ---
var _drawing: bool = false
var _panning: bool = false
var _pan_last: Vector2 = Vector2.ZERO
var _space_held: bool = false

## Live touch contacts, by finger index.
var _touches: Dictionary[int, Vector2] = {}
var _pinch_distance: float = 0.0
var _pinch_centre: Vector2 = Vector2.ZERO
var _gesture_active: bool = false

## True once any event has proven a stylus is in use (see the class docs).
var _stylus_seen: bool = false
## True while the stylus is physically in contact.
var _stylus_down: bool = false


func _ready() -> void:
	# Nearest-neighbour is non-negotiable: any filtering would blur the artwork
	# into colours that are not in it.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	_prefs = PPSettings.get_instance()
	set_process(true)


func bind(state: PPAppState) -> void:
	app = state
	app.document_changed.connect(_on_document_changed)
	if app.document != null:
		_on_document_changed(app.document)


func _process(_delta: float) -> void:
	# The marching ants animate, so the canvas has to keep repainting while a
	# selection exists. Otherwise it is entirely event-driven.
	if _document != null and not _document.selection.is_empty():
		queue_redraw()


func _on_document_changed(document: PPDocument) -> void:
	if _document != null:
		if _document.canvas_changed.is_connected(_on_canvas_changed):
			_document.canvas_changed.disconnect(_on_canvas_changed)
		if _document.selection_changed.is_connected(_on_selection_changed):
			_document.selection_changed.disconnect(_on_selection_changed)
		if _document.structure_changed.is_connected(_on_structure_changed):
			_document.structure_changed.disconnect(_on_structure_changed)
		if _document.active_cel_changed.is_connected(_on_structure_changed):
			_document.active_cel_changed.disconnect(_on_structure_changed)

	_document = document
	_document.canvas_changed.connect(_on_canvas_changed)
	_document.selection_changed.connect(_on_selection_changed)
	_document.structure_changed.connect(_on_structure_changed)
	_document.active_cel_changed.connect(_on_structure_changed)

	_selection_dirty = true
	_onion_key = ""
	zoom_to_fit()


func _on_canvas_changed(_rect: Rect2i) -> void:
	queue_redraw()


func _on_selection_changed() -> void:
	_selection_dirty = true
	queue_redraw()


func _on_structure_changed() -> void:
	_onion_key = ""
	queue_redraw()


# --- Transform --------------------------------------------------------------

func canvas_to_screen(point: Vector2) -> Vector2:
	return origin + point * zoom


func screen_to_canvas(point: Vector2) -> Vector2:
	return (point - origin) / zoom


func get_canvas_rect() -> Rect2:
	if _document == null:
		return Rect2()
	return Rect2(origin, Vector2(_document.sprite.size) * zoom)


func zoom_to_fit() -> void:
	if _document == null or size.x <= 0.0 or size.y <= 0.0:
		return

	var sprite_size: Vector2 = Vector2(_document.sprite.size)
	if sprite_size.x <= 0.0 or sprite_size.y <= 0.0:
		return

	var margin: float = 48.0
	var fit: float = minf(
		(size.x - margin) / sprite_size.x, (size.y - margin) / sprite_size.y
	)
	# Snap to a whole multiple when zoomed in, so pixels stay square and crisp.
	if fit >= 1.0:
		fit = floorf(fit)
	set_zoom(clampf(fit, MIN_ZOOM, MAX_ZOOM), size * 0.5)
	_centre()


func _centre() -> void:
	if _document == null:
		return
	var sprite_size: Vector2 = Vector2(_document.sprite.size) * zoom
	origin = ((size - sprite_size) * 0.5).round()
	queue_redraw()


## Zooms about a fixed screen point, so the pixel under the cursor stays put.
func set_zoom(next: float, anchor: Vector2) -> void:
	var clamped: float = clampf(next, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(clamped, zoom):
		return

	var before: Vector2 = screen_to_canvas(anchor)
	zoom = clamped
	var after: Vector2 = screen_to_canvas(anchor)
	origin += (after - before) * zoom

	zoom_changed.emit(zoom)
	queue_redraw()


func zoom_in() -> void:
	set_zoom(zoom * ZOOM_STEP, size * 0.5)


func zoom_out() -> void:
	set_zoom(zoom / ZOOM_STEP, size * 0.5)


func reset_view() -> void:
	zoom_to_fit()


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	if _document == null:
		return

	var rect: Rect2 = get_canvas_rect()

	_draw_checkerboard(rect)
	_draw_onion(rect, true)
	draw_texture_rect(_document.composite_texture, rect, false)
	_draw_onion(rect, false)
	_draw_grid(rect)
	_draw_selection()
	_draw_cursor()
	_draw_border(rect)


func _draw_checkerboard(rect: Rect2) -> void:
	_rebuild_checker()
	if _checker != null:
		draw_texture_rect(_checker, rect, false)


func _rebuild_checker() -> void:
	var size_key: String = "%d:%d:%d" % [
		_document.sprite.size.x, _document.sprite.size.y, _prefs.checker_size
	]
	if _checker != null and _checker_key == size_key:
		return
	_checker_key = size_key

	# The checker is built at canvas resolution so it scales with zoom -- the
	# convention every pixel editor uses, because it gives the artist a stable
	# sense of scale.
	var sprite_size: Vector2i = _document.sprite.size
	var image: Image = Image.create_empty(
		sprite_size.x, sprite_size.y, false, Image.FORMAT_RGBA8
	)
	var cell: int = maxi(1, _prefs.checker_size)

	for y: int in range(sprite_size.y):
		for x: int in range(sprite_size.x):
			var dark: bool = ((x / cell) + (y / cell)) % 2 == 1
			image.set_pixel(
				x, y, _prefs.checker_dark if dark else _prefs.checker_light
			)

	_checker = ImageTexture.create_from_image(image)


func _draw_onion(rect: Rect2, before: bool) -> void:
	if not _prefs.onion_enabled:
		return
	_rebuild_onion()

	var layers: Array[ImageTexture] = _onion_before if before else _onion_after
	for i: int in range(layers.size()):
		if layers[i] == null:
			continue
		# Nearer frames are more opaque, so the immediate neighbour reads as the
		# strongest ghost.
		var falloff: float = 1.0 - (float(i) / float(layers.size() + 1))
		draw_texture_rect(
			layers[i], rect, false, Color(1.0, 1.0, 1.0, falloff)
		)


func _rebuild_onion() -> void:
	var key: String = "%d:%d:%d:%.2f:%d" % [
		_document.active_frame,
		_prefs.onion_before,
		_prefs.onion_after,
		_prefs.onion_opacity,
		_document.sprite.frame_count(),
	]
	if _onion_key == key:
		return
	_onion_key = key

	_onion_before.clear()
	_onion_after.clear()

	for i: int in range(1, _prefs.onion_before + 1):
		var index: int = _document.active_frame - i
		if index < 0:
			break
		_onion_before.append(
			ImageTexture.create_from_image(
				PPCompositor.flatten_onion(
					_document.sprite, index, _prefs.onion_before_tint, _prefs.onion_opacity
				)
			)
		)

	for i: int in range(1, _prefs.onion_after + 1):
		var index: int = _document.active_frame + i
		if index >= _document.sprite.frame_count():
			break
		_onion_after.append(
			ImageTexture.create_from_image(
				PPCompositor.flatten_onion(
					_document.sprite, index, _prefs.onion_after_tint, _prefs.onion_opacity
				)
			)
		)


func _draw_grid(rect: Rect2) -> void:
	var sprite_size: Vector2i = _document.sprite.size

	if _prefs.show_pixel_grid and zoom >= PIXEL_GRID_MIN_ZOOM:
		var faint: Color = Color(1.0, 1.0, 1.0, 0.08)
		for x: int in range(1, sprite_size.x):
			var sx: float = rect.position.x + float(x) * zoom
			draw_line(
				Vector2(sx, rect.position.y), Vector2(sx, rect.end.y), faint, 1.0
			)
		for y: int in range(1, sprite_size.y):
			var sy: float = rect.position.y + float(y) * zoom
			draw_line(
				Vector2(rect.position.x, sy), Vector2(rect.end.x, sy), faint, 1.0
			)

	if not _prefs.show_grid:
		return

	var grid: Vector2i = _prefs.grid_size
	if grid.x <= 0 or grid.y <= 0:
		return

	var strong: Color = Color(0.4, 0.7, 1.0, 0.35)
	var x_step: int = grid.x
	while x_step < sprite_size.x:
		var gx: float = rect.position.x + float(x_step) * zoom
		draw_line(Vector2(gx, rect.position.y), Vector2(gx, rect.end.y), strong, 1.0)
		x_step += grid.x

	var y_step: int = grid.y
	while y_step < sprite_size.y:
		var gy: float = rect.position.y + float(y_step) * zoom
		draw_line(Vector2(rect.position.x, gy), Vector2(rect.end.x, gy), strong, 1.0)
		y_step += grid.y


func _draw_selection() -> void:
	if _document.selection.is_empty():
		return

	if _selection_dirty:
		_selection_outline = _document.selection.build_outline()
		_selection_dirty = false

	# Marching ants without a shader: the dash colour alternates along the edge
	# and the phase advances with time, which reads as motion.
	var phase: int = int(Time.get_ticks_msec() / 60.0)

	var i: int = 0
	while i + 1 < _selection_outline.size():
		var a: Vector2 = canvas_to_screen(_selection_outline[i])
		var b: Vector2 = canvas_to_screen(_selection_outline[i + 1])

		var key: int = (
			int(_selection_outline[i].x) + int(_selection_outline[i].y) + phase
		)
		var light: bool = (key / 4) % 2 == 0
		draw_line(a, b, Color.WHITE if light else Color.BLACK, 1.0)
		i += 2


func _draw_cursor() -> void:
	if not _hover_valid or app == null or _panning:
		return

	var tool: PPTool = app.get_tool()
	if tool == null:
		return

	var pointer: PPPointer = PPPointer.new()
	pointer.position = Vector2(_hover_cell)
	var cells: Array[Vector2i] = tool.get_cursor_cells(app.context, pointer)
	if cells.is_empty():
		return

	# Outline the exact cells the brush would touch. At high zoom this is a
	# precise footprint; at low zoom it degrades to a dot, which is still the
	# truth.
	for cell: Vector2i in cells:
		var top_left: Vector2 = canvas_to_screen(Vector2(cell))
		var cell_rect: Rect2 = Rect2(top_left, Vector2(zoom, zoom))
		draw_rect(cell_rect, Color(1.0, 1.0, 1.0, 0.85), false, 1.0)
		draw_rect(cell_rect.grow(-1.0), Color(0.0, 0.0, 0.0, 0.5), false, 1.0)


func _draw_border(rect: Rect2) -> void:
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.6), false, 2.0)


# --- Input ------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if _document == null or app == null:
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)
	elif event is InputEventKey:
		_handle_key(event as InputEventKey)


func _handle_key(event: InputEventKey) -> void:
	if event.keycode == KEY_SPACE:
		_space_held = event.pressed
		accept_event()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		set_zoom(zoom * ZOOM_STEP, event.position)
		accept_event()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		set_zoom(zoom / ZOOM_STEP, event.position)
		accept_event()
		return

	# Middle-drag, or space-drag, pans. Both are universal muscle memory.
	var wants_pan: bool = (
		event.button_index == MOUSE_BUTTON_MIDDLE
		or (event.button_index == MOUSE_BUTTON_LEFT and _space_held)
	)
	if wants_pan:
		_panning = event.pressed
		_pan_last = event.position
		accept_event()
		return

	if (
		event.button_index != MOUSE_BUTTON_LEFT
		and event.button_index != MOUSE_BUTTON_RIGHT
	):
		return

	grab_focus()
	var pointer: PPPointer = _pointer_from_mouse(event.position, event)
	pointer.secondary = event.button_index == MOUSE_BUTTON_RIGHT

	if event.pressed:
		_drawing = true
		app.get_tool().press(app.context, pointer)
	elif _drawing:
		_drawing = false
		app.get_tool().release(app.context, pointer)

	accept_event()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _panning:
		origin += event.position - _pan_last
		_pan_last = event.position
		queue_redraw()
		accept_event()
		return

	_note_stylus(event.tilt, event.pen_inverted)
	_update_hover(event.position)

	if not _drawing:
		return

	var pointer: PPPointer = _pointer_from_mouse(event.position, event)
	pointer.secondary = (
		event.button_mask & MOUSE_BUTTON_MASK_RIGHT
	) != 0
	app.get_tool().drag(app.context, pointer)
	accept_event()


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# Palm rejection: while the pen is down, any new contact is a hand.
		if _stylus_down and _prefs.palm_rejection:
			return

		_touches[event.index] = event.position

		if _touches.size() >= 2:
			# A second finger turns the gesture into navigation. Whatever the
			# first finger had started drawing is abandoned rather than
			# committed, which is what the user means by "no, pan".
			_cancel_stroke()
			_begin_pinch()
			return

		if _finger_draws():
			grab_focus()
			_drawing = true
			app.get_tool().press(app.context, _pointer_from_touch(event.position, 1.0))
		else:
			_panning = true
			_pan_last = event.position
		return

	_touches.erase(event.index)

	if _touches.size() < 2:
		_gesture_active = false
	if _touches.is_empty():
		if _drawing:
			_drawing = false
			app.get_tool().release(
				app.context, _pointer_from_touch(event.position, 1.0)
			)
		_panning = false
		_hover_valid = false
		queue_redraw()


func _handle_drag(event: InputEventScreenDrag) -> void:
	# On iOS the Apple Pencil arrives here, carrying real pressure and tilt.
	_note_stylus(event.tilt, event.pen_inverted)
	if _touches.has(event.index):
		_touches[event.index] = event.position

	if _touches.size() >= 2:
		_update_pinch()
		return

	if _panning:
		origin += event.relative
		queue_redraw()
		return

	if not _drawing:
		return

	var pointer: PPPointer = _pointer_from_touch(event.position, event.pressure)
	pointer.tilt = event.tilt
	pointer.inverted = event.pen_inverted
	_update_hover(event.position)
	app.get_tool().drag(app.context, pointer)


func _begin_pinch() -> void:
	var points: Array[Vector2] = []
	for value: Vector2 in _touches.values():
		points.append(value)
	if points.size() < 2:
		return
	_pinch_distance = points[0].distance_to(points[1])
	_pinch_centre = (points[0] + points[1]) * 0.5
	_gesture_active = true
	_panning = false


func _update_pinch() -> void:
	var points: Array[Vector2] = []
	for value: Vector2 in _touches.values():
		points.append(value)
	if points.size() < 2 or not _gesture_active:
		return

	var distance: float = points[0].distance_to(points[1])
	var centre: Vector2 = (points[0] + points[1]) * 0.5

	# Two fingers do both at once: the midpoint drags the canvas, the spread
	# zooms it. Separating them into distinct gestures would feel broken.
	origin += centre - _pinch_centre

	if _pinch_distance > 1.0 and distance > 1.0:
		set_zoom(zoom * (distance / _pinch_distance), centre)

	_pinch_distance = distance
	_pinch_centre = centre
	queue_redraw()


func _cancel_stroke() -> void:
	if not _drawing:
		return
	_drawing = false
	app.get_tool().cancel(app.context)


## A finger paints only while no stylus has ever been seen, or when the user has
## explicitly turned finger-panning off.
func _finger_draws() -> bool:
	if not _prefs.finger_pans:
		return true
	return not _stylus_seen


func _note_stylus(tilt: Vector2, inverted: bool) -> void:
	if tilt != Vector2.ZERO or inverted:
		_stylus_seen = true


func _pointer_from_mouse(position: Vector2, event: InputEventMouse) -> PPPointer:
	var pointer: PPPointer = PPPointer.new()
	pointer.position = screen_to_canvas(position)
	pointer.shift = event.shift_pressed
	pointer.control = event.ctrl_pressed
	pointer.alt = event.alt_pressed

	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		pointer.tilt = motion.tilt
		pointer.inverted = motion.pen_inverted
		pointer.pressure = _resolve_pressure(motion.pressure)
	else:
		pointer.pressure = 1.0

	return pointer


func _pointer_from_touch(position: Vector2, pressure: float) -> PPPointer:
	var pointer: PPPointer = PPPointer.new()
	pointer.position = screen_to_canvas(position)
	pointer.is_touch = true
	pointer.pressure = _resolve_pressure(pressure)
	return pointer


## A mouse reports no pressure at all, which must not be read as "feather-light".
## Zero means "this device has no pressure sensor", so treat it as a full press.
func _resolve_pressure(raw: float) -> float:
	if not _prefs.pressure_enabled:
		return 1.0
	if raw <= 0.0:
		return 1.0
	return clampf(raw, 0.0, 1.0)


func _update_hover(position: Vector2) -> void:
	var cell: Vector2i = Vector2i(screen_to_canvas(position).floor())
	if cell == _hover_cell and _hover_valid:
		return
	_hover_cell = cell
	_hover_valid = _document.sprite.get_bounds().has_point(cell)
	pointer_moved.emit(cell)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_valid = false
		queue_redraw()
	elif what == NOTIFICATION_RESIZED and _document != null:
		queue_redraw()
