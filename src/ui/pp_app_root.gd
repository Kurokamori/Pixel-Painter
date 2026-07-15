class_name PPAppRoot
extends Control

## Wires the editor together: menus, shortcuts, file dialogs, and sync.
##
## The panels do not know about each other -- they all bind to PPAppState, and
## everything that mutates the document goes through PPHistory. This node is the
## only place that knows the scene layout.

## Menu ids, matching the PopupMenu items authored in app_root.tscn.
enum MenuId {
	NEW = 0,
	OPEN = 1,
	SAVE = 2,
	SAVE_AS = 3,
	IMPORT = 4,
	EXPORT = 5,
	QUIT = 6,

	UNDO = 10,
	REDO = 11,
	CUT = 12,
	COPY = 13,
	PASTE = 14,
	DELETE = 15,
	SELECT_ALL = 16,
	DESELECT = 17,
	INVERT_SELECTION = 18,

	RESIZE_CANVAS = 20,
	SCALE_SPRITE = 21,
	CROP_TO_SELECTION = 22,
	FLIP_H = 23,
	FLIP_V = 24,
	ROTATE_CW = 25,
	ROTATE_180 = 26,

	ZOOM_IN = 30,
	ZOOM_OUT = 31,
	ZOOM_FIT = 32,
	TOGGLE_GRID = 33,
	TOGGLE_PIXEL_GRID = 34,
	TOGGLE_TIMELINE = 35,
}

## Tool shortcuts, in the layout every pixel editor shares.
const TOOL_KEYS: Dictionary[int, StringName] = {
	KEY_B: &"pencil",
	KEY_E: &"eraser",
	KEY_G: &"bucket",
	KEY_I: &"eyedropper",
	KEY_L: &"line",
	KEY_R: &"rectangle",
	KEY_O: &"ellipse",
	KEY_D: &"gradient",
	KEY_M: &"select_rect",
	KEY_Q: &"lasso",
	KEY_W: &"magic_wand",
	KEY_V: &"move",
}

var _prefs: PPSettings = null
## Set while a save dialog is open on behalf of an export, so the same dialog
## can serve both without two nearly identical FileDialogs in the scene.
var _pending_export: PPExportDialog.Config = null
var _pending_sync_bytes: PackedByteArray = PackedByteArray()

@onready var app: PPAppState = %AppState
@onready var sync: PPSyncService = %SyncService

@onready var _canvas: PPCanvasView = %CanvasView
@onready var _tools: PPToolsPanel = %ToolsPanel
@onready var _options: PPToolOptionsBar = %ToolOptionsBar
@onready var _color: PPColorPanel = %ColorPanel
@onready var _palette: PPPalettePanel = %PalettePanel
@onready var _layers: PPLayersPanel = %LayersPanel
@onready var _timeline: PPTimelinePanel = %TimelinePanel
## A ScrollContainer, not a plain column: the colour picker alone insists on a
## 509px minimum height, and stacked with the palette and layers that exceeds a
## laptop's viewport -- which made the whole layout grow past the window and
## push the menu bar off the top of the screen. Scrolling contains it, and is
## also what makes the dock usable on an iPad in portrait.
@onready var _right_dock: ScrollContainer = %RightDock

@onready var _file_button: Button = %FileButton
@onready var _edit_button: Button = %EditButton
@onready var _sprite_button: Button = %SpriteButton
@onready var _view_button: Button = %ViewButton
@onready var _undo_button: Button = %UndoButton
@onready var _redo_button: Button = %RedoButton
@onready var _sync_button: Button = %SyncButton
@onready var _panels_button: Button = %PanelsButton
@onready var _title: Label = %TitleLabel
@onready var _status: Label = %StatusLabel

@onready var _file_menu: PopupMenu = %FileMenu
@onready var _edit_menu: PopupMenu = %EditMenu
@onready var _sprite_menu: PopupMenu = %SpriteMenu
@onready var _view_menu: PopupMenu = %ViewMenu

@onready var _new_dialog: PPNewSpriteDialog = %NewSpriteDialog
@onready var _export_dialog: PPExportDialog = %ExportDialog
@onready var _resize_dialog: PPResizeDialog = %ResizeDialog
@onready var _sync_dialog: PPSyncDialog = %SyncDialog
@onready var _open_dialog: FileDialog = %OpenDialog
@onready var _save_dialog: FileDialog = %SaveDialog
@onready var _palette_open: FileDialog = %PaletteOpenDialog
@onready var _palette_save: FileDialog = %PaletteSaveDialog
@onready var _message: AcceptDialog = %MessageDialog
@onready var _incoming: ConfirmationDialog = %IncomingDialog


func _ready() -> void:
	_prefs = PPSettings.get_instance()

	_canvas.bind(app)
	_tools.bind(app)
	_options.bind(app)
	_color.bind(app)
	_palette.bind(app)
	_layers.bind(app)
	_timeline.bind(app)
	_sync_dialog.bind(sync)

	_bind_menus()
	_bind_dialogs()
	_bind_toolbar()

	app.document_changed.connect(_on_document_changed)
	app.status_message.connect(_on_status)
	_on_document_changed(app.document)

	_view_menu.set_item_checked(_view_menu.get_item_index(MenuId.TOGGLE_GRID), _prefs.show_grid)
	_view_menu.set_item_checked(
		_view_menu.get_item_index(MenuId.TOGGLE_PIXEL_GRID), _prefs.show_pixel_grid
	)

	get_window().title = "Pixel Painter"


func _bind_toolbar() -> void:
	_file_button.pressed.connect(func() -> void: _popup_under(_file_menu, _file_button))
	_edit_button.pressed.connect(func() -> void: _popup_under(_edit_menu, _edit_button))
	_sprite_button.pressed.connect(func() -> void: _popup_under(_sprite_menu, _sprite_button))
	_view_button.pressed.connect(func() -> void: _popup_under(_view_menu, _view_button))

	_undo_button.pressed.connect(func() -> void: app.undo())
	_redo_button.pressed.connect(func() -> void: app.redo())
	_sync_button.pressed.connect(func() -> void: _sync_dialog.open())
	_panels_button.toggled.connect(func(on: bool) -> void: _right_dock.visible = on)


func _bind_menus() -> void:
	_file_menu.id_pressed.connect(_on_menu)
	_edit_menu.id_pressed.connect(_on_menu)
	_sprite_menu.id_pressed.connect(_on_menu)
	_view_menu.id_pressed.connect(_on_menu)


func _bind_dialogs() -> void:
	_new_dialog.create_requested.connect(_on_new_sprite)
	_export_dialog.export_requested.connect(_on_export_requested)
	_resize_dialog.resize_requested.connect(_on_resize)
	_resize_dialog.scale_requested.connect(_on_scale)
	_sync_dialog.send_requested.connect(_on_send)

	_open_dialog.filters = PPFileService.open_filters()
	_open_dialog.file_selected.connect(_on_open_selected)

	_save_dialog.filters = PPFileService.save_filters()
	_save_dialog.file_selected.connect(_on_save_selected)

	_palette_open.filters = PackedStringArray(
		["*.gpl,*.pal,*.hex,*.png;Palette files"]
	)
	_palette_open.file_selected.connect(_on_palette_open_selected)

	_palette_save.filters = PackedStringArray(
		["*.gpl;GIMP Palette", "*.pal;JASC Palette", "*.hex;Hex list", "*.png;PNG strip"]
	)
	_palette_save.file_selected.connect(_on_palette_save_selected)

	_palette.load_palette_requested.connect(func() -> void: _palette_open.popup_centered())
	_palette.save_palette_requested.connect(func() -> void: _palette_save.popup_centered())

	sync.project_offered.connect(_on_project_offered)
	sync.transfer_finished.connect(
		func(_peer: PPSyncPeer, _ok: bool, message: String) -> void: _on_status(message)
	)


func _popup_under(menu: PopupMenu, button: Button) -> void:
	var at: Vector2 = button.global_position + Vector2(0.0, button.size.y)
	menu.position = Vector2i(get_window().position) + Vector2i(at)
	menu.reset_size()
	menu.popup()


func _on_document_changed(document: PPDocument) -> void:
	if document == null:
		return
	if not document.dirty_changed.is_connected(_refresh_title):
		document.dirty_changed.connect(_refresh_title)
	if not document.history.changed.is_connected(_refresh_history):
		document.history.changed.connect(_refresh_history)

	_refresh_title(document.is_dirty())
	_refresh_history()


func _refresh_title(_dirty: bool = false) -> void:
	var document: PPDocument = app.document
	if document == null:
		return
	var mark: String = "•  " if document.is_dirty() else ""
	_title.text = "%s%s   %d × %d" % [
		mark, document.get_title(), document.sprite.size.x, document.sprite.size.y
	]


func _refresh_history() -> void:
	_undo_button.disabled = not app.can_undo()
	_redo_button.disabled = not app.can_redo()


func _on_status(text: String) -> void:
	_status.text = text


# --- Menu actions -----------------------------------------------------------

func _on_menu(id: int) -> void:
	var document: PPDocument = app.document

	match id:
		MenuId.NEW:
			_new_dialog.popup_centered()
		MenuId.OPEN:
			_open_dialog.popup_centered()
		MenuId.SAVE:
			_save()
		MenuId.SAVE_AS:
			_pending_export = null
			_save_dialog.filters = PPFileService.save_filters()
			_save_dialog.popup_centered()
		MenuId.IMPORT:
			_open_dialog.popup_centered()
		MenuId.EXPORT:
			_export_dialog.open_for(document)
		MenuId.QUIT:
			get_tree().quit()

		MenuId.UNDO:
			app.undo()
		MenuId.REDO:
			app.redo()
		MenuId.CUT:
			PPEditOps.cut(document)
		MenuId.COPY:
			PPEditOps.copy(document)
		MenuId.PASTE:
			PPEditOps.paste(document, _paste_anchor())
		MenuId.DELETE:
			PPEditOps.delete_selection(document)
		MenuId.SELECT_ALL:
			PPEditOps.select_all(document)
		MenuId.DESELECT:
			PPEditOps.select_none(document)
		MenuId.INVERT_SELECTION:
			PPEditOps.invert_selection(document)

		MenuId.RESIZE_CANVAS:
			_resize_dialog.open_for(document, PPResizeDialog.ResizeMode.CANVAS)
		MenuId.SCALE_SPRITE:
			_resize_dialog.open_for(document, PPResizeDialog.ResizeMode.SCALE)
		MenuId.CROP_TO_SELECTION:
			_crop_to_selection()
		MenuId.FLIP_H:
			document.history.push(PPSpriteCommands.flip(document.sprite, true))
		MenuId.FLIP_V:
			document.history.push(PPSpriteCommands.flip(document.sprite, false))
		MenuId.ROTATE_CW:
			document.history.push(PPSpriteCommands.rotate(document.sprite, 90))
		MenuId.ROTATE_180:
			document.history.push(PPSpriteCommands.rotate(document.sprite, 180))

		MenuId.ZOOM_IN:
			_canvas.zoom_in()
		MenuId.ZOOM_OUT:
			_canvas.zoom_out()
		MenuId.ZOOM_FIT:
			_canvas.reset_view()
		MenuId.TOGGLE_GRID:
			_prefs.show_grid = not _prefs.show_grid
			_prefs.save_settings()
			_view_menu.set_item_checked(
				_view_menu.get_item_index(MenuId.TOGGLE_GRID), _prefs.show_grid
			)
			_canvas.queue_redraw()
		MenuId.TOGGLE_PIXEL_GRID:
			_prefs.show_pixel_grid = not _prefs.show_pixel_grid
			_prefs.save_settings()
			_view_menu.set_item_checked(
				_view_menu.get_item_index(MenuId.TOGGLE_PIXEL_GRID), _prefs.show_pixel_grid
			)
			_canvas.queue_redraw()
		MenuId.TOGGLE_TIMELINE:
			_timeline.visible = not _timeline.visible
			_view_menu.set_item_checked(
				_view_menu.get_item_index(MenuId.TOGGLE_TIMELINE), _timeline.visible
			)


## Pastes into the top-left of the current selection when there is one, so a
## copy/paste in place lands where the user is looking rather than at the origin.
func _paste_anchor() -> Vector2i:
	var selection: PPSelection = app.document.selection
	if selection.is_empty():
		return Vector2i.ZERO
	return selection.get_bounds().position


func _crop_to_selection() -> void:
	var document: PPDocument = app.document
	if document.selection.is_empty():
		_warn("Nothing is selected — select an area first.")
		return
	document.history.push(
		PPSpriteCommands.crop(document.sprite, document.selection.get_bounds())
	)


# --- Files ------------------------------------------------------------------

func _save() -> void:
	var document: PPDocument = app.document
	if document.path.is_empty():
		_pending_export = null
		_save_dialog.filters = PPFileService.save_filters()
		_save_dialog.popup_centered()
		return
	_write(document.path)


func _write(path: String) -> void:
	var error: Error = PPFileService.save(app.document, path)
	if error != OK:
		_warn("Could not save to %s (error %d)." % [path.get_file(), error])
		return
	_prefs.add_recent_file(path)
	_refresh_title()
	_on_status("Saved %s" % path.get_file())


func _on_open_selected(path: String) -> void:
	var document: PPDocument = PPFileService.open(path)
	if document == null:
		_warn("Could not open %s. It may be corrupt or an unsupported format." % path.get_file())
		return
	app.set_document(document)
	_on_status("Opened %s" % path.get_file())


func _on_save_selected(path: String) -> void:
	if _pending_export != null:
		var config: PPExportDialog.Config = _pending_export
		_pending_export = null
		_perform_export(config, path)
		return
	_write(PPFileService.ensure_extension(path))


func _on_new_sprite(size: Vector2i, palette: PPPalette) -> void:
	app.new_document(size, palette)
	_on_status("New %d × %d sprite" % [size.x, size.y])


func _on_palette_open_selected(path: String) -> void:
	var palette: PPPalette = PPPaletteIO.load_palette(path)
	if palette == null:
		_warn("Could not read a palette from %s." % path.get_file())
		return
	_palette.apply_palette(palette)
	_on_status("Loaded palette %s (%d colours)" % [palette.name, palette.size()])


func _on_palette_save_selected(path: String) -> void:
	var error: Error = PPPaletteIO.save_palette(_palette.get_palette(), path)
	if error != OK:
		_warn("Could not save the palette (error %d)." % error)
		return
	_on_status("Saved palette %s" % path.get_file())


# --- Export -----------------------------------------------------------------

func _on_export_requested(config: PPExportDialog.Config) -> void:
	_pending_export = config
	_save_dialog.filters = PackedStringArray(
		["*.%s;Export" % config.get_extension()]
	)
	_save_dialog.popup_centered()


func _perform_export(config: PPExportDialog.Config, path: String) -> void:
	var target: String = PPFileService.ensure_extension(path, config.get_extension())
	var document: PPDocument = app.document
	var error: Error = OK

	match config.format:
		PPExportDialog.Format.PNG_FRAME:
			error = PPExportIO.export_png(
				document, target, document.active_frame, config.scale
			)
		PPExportDialog.Format.PNG_FRAMES:
			error = PPExportIO.export_frames(document, target, config.scale)
		PPExportDialog.Format.SPRITESHEET:
			error = PPExportIO.export_spritesheet(document, target, config.sheet)
		PPExportDialog.Format.GIF:
			error = PPExportIO.export_gif(document, target, config.scale)

	if error != OK:
		_warn("Export failed (error %d)." % error)
		return
	_on_status("Exported %s" % target.get_file())


# --- Sprite geometry --------------------------------------------------------

func _on_resize(size: Vector2i, offset: Vector2i) -> void:
	app.document.history.push(
		PPSpriteCommands.resize_canvas(app.document.sprite, size, offset)
	)
	_canvas.reset_view()
	_refresh_title()


func _on_scale(size: Vector2i) -> void:
	app.document.history.push(
		PPSpriteCommands.scale_sprite(app.document.sprite, size)
	)
	_canvas.reset_view()
	_refresh_title()


# --- Sync -------------------------------------------------------------------

func _on_send(peer: PPSyncPeer) -> void:
	var error: Error = sync.send_document(peer, app.document)
	if error != OK:
		_warn("Could not start the transfer (error %d)." % error)


func _on_project_offered(
	from: PPSyncPeer, bytes: PackedByteArray, project_name: String
) -> void:
	# Never open an incoming sprite over unsaved work without asking. Auto-accept
	# is opt-in for exactly this reason.
	if _prefs.sync_auto_accept and not app.document.is_dirty():
		_accept_incoming(bytes)
		return

	_pending_sync_bytes = bytes
	_incoming.dialog_text = "%s wants to send you a sprite (%s).\n\nOpen it?" % [
		from.name, project_name
	]
	if app.document.is_dirty():
		_incoming.dialog_text += "\n\nYour current sprite has unsaved changes."

	if not _incoming.confirmed.is_connected(_on_incoming_confirmed):
		_incoming.confirmed.connect(_on_incoming_confirmed)
	_incoming.popup_centered()


func _on_incoming_confirmed() -> void:
	_accept_incoming(_pending_sync_bytes)
	_pending_sync_bytes = PackedByteArray()


func _accept_incoming(bytes: PackedByteArray) -> void:
	var document: PPDocument = PPProjectIO.decode(bytes)
	if document == null:
		_warn("The incoming sprite could not be read.")
		return
	app.set_document(document)
	_on_status("Received a sprite")


func _warn(message: String) -> void:
	_message.dialog_text = message
	_message.popup_centered()


# --- Shortcuts --------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	if key.ctrl_pressed or key.meta_pressed:
		_handle_command_key(key)
		return

	# Bare keys: tools and navigation. Never while typing in a text field.
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit or focused is SpinBox:
		return

	if TOOL_KEYS.has(key.keycode):
		app.set_tool(TOOL_KEYS[key.keycode])
		get_viewport().set_input_as_handled()
		return

	match key.keycode:
		KEY_X:
			app.settings.swap_colors()
		KEY_BRACKETLEFT:
			app.settings.set_brush_size(app.settings.brush_size - 1)
		KEY_BRACKETRIGHT:
			app.settings.set_brush_size(app.settings.brush_size + 1)
		KEY_DELETE, KEY_BACKSPACE:
			PPEditOps.delete_selection(app.document)
		KEY_ESCAPE:
			app.get_tool().cancel(app.context)
			PPEditOps.select_none(app.document)
		KEY_ENTER, KEY_KP_ENTER:
			app.toggle_playing()
		KEY_COMMA:
			app.document.active_frame -= 1
		KEY_PERIOD:
			app.document.active_frame += 1
		KEY_HOME:
			app.document.active_frame = 0
		KEY_END:
			app.document.active_frame = app.document.sprite.frame_count() - 1
		KEY_LEFT:
			PPEditOps.nudge(app.document, Vector2i(-1, 0))
		KEY_RIGHT:
			PPEditOps.nudge(app.document, Vector2i(1, 0))
		KEY_UP:
			PPEditOps.nudge(app.document, Vector2i(0, -1))
		KEY_DOWN:
			PPEditOps.nudge(app.document, Vector2i(0, 1))
		_:
			return

	get_viewport().set_input_as_handled()


func _handle_command_key(key: InputEventKey) -> void:
	match key.keycode:
		KEY_Z:
			if key.shift_pressed:
				app.redo()
			else:
				app.undo()
		KEY_Y:
			app.redo()
		KEY_N:
			_on_menu(MenuId.NEW)
		KEY_O:
			_on_menu(MenuId.OPEN)
		KEY_S:
			if key.shift_pressed:
				_on_menu(MenuId.SAVE_AS)
			else:
				_on_menu(MenuId.SAVE)
		KEY_E:
			_on_menu(MenuId.EXPORT)
		KEY_X:
			_on_menu(MenuId.CUT)
		KEY_C:
			_on_menu(MenuId.COPY)
		KEY_V:
			_on_menu(MenuId.PASTE)
		KEY_A:
			_on_menu(MenuId.SELECT_ALL)
		KEY_D:
			_on_menu(MenuId.DESELECT)
		KEY_I:
			_on_menu(MenuId.INVERT_SELECTION)
		KEY_EQUAL, KEY_PLUS:
			_canvas.zoom_in()
		KEY_MINUS:
			_canvas.zoom_out()
		KEY_0:
			_canvas.reset_view()
		_:
			return

	get_viewport().set_input_as_handled()
