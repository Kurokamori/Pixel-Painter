class_name PPAppState
extends Node

## The editor's shared state: the open document, the tool registry, the active
## tool, and animation playback.
##
## Every panel binds to this and to nothing else, so a panel never needs to know
## another panel exists. Mounted as a node in app_root.tscn.

signal document_changed(document: PPDocument)
signal tool_changed(tool: PPTool)
signal status_message(text: String)
signal playback_changed(playing: bool)

var document: PPDocument = null
var settings: PPToolSettings = PPToolSettings.new()
var registry: PPToolRegistry = PPToolRegistry.new()
var context: PPToolContext = null

var active_tool_id: StringName = &"pencil"

## Playback
var playing: bool = false
var loop_playback: bool = true
var _playback_elapsed: float = 0.0

var _prefs: PPSettings = null


func _ready() -> void:
	_prefs = PPSettings.get_instance()
	set_process(true)
	new_document(Vector2i(64, 64), PPDefaultPalettes.get_default())


func _process(delta: float) -> void:
	if not playing or document == null:
		return
	if document.sprite.frame_count() <= 1:
		return

	_playback_elapsed += delta * 1000.0
	var current: PPFrame = document.sprite.get_frame(document.active_frame)
	if _playback_elapsed < float(current.duration_ms):
		return

	_playback_elapsed -= float(current.duration_ms)
	_advance_frame()


func _advance_frame() -> void:
	var next: int = document.active_frame + 1
	var last: int = document.sprite.frame_count() - 1

	# Playback follows the tag under the playhead, if there is one: that is what
	# makes scrubbing a "walk" cycle actually loop the walk and not the whole
	# sprite sheet.
	var tag: PPTag = _active_tag()
	if tag != null:
		last = tag.to_frame
		if next > last:
			next = tag.from_frame if loop_playback else last
	elif next > last:
		if loop_playback:
			next = 0
		else:
			next = last
			set_playing(false)

	document.active_frame = next


func _active_tag() -> PPTag:
	if document == null:
		return null
	for tag: PPTag in document.sprite.tags:
		if tag.contains(document.active_frame):
			return tag
	return null


# --- Document ---------------------------------------------------------------

func new_document(size: Vector2i, palette: PPPalette) -> void:
	set_document(PPDocument.create(size, palette))


func set_document(next: PPDocument) -> void:
	if next == null:
		return

	set_playing(false)
	document = next
	document.history.limit = _prefs.undo_limit
	context = PPToolContext.create(document, settings)
	context.status_changed.connect(_on_status)

	document_changed.emit(document)
	if not document.path.is_empty():
		_prefs.add_recent_file(document.path)


func get_tool() -> PPTool:
	return registry.get_tool(active_tool_id)


func set_tool(id: StringName) -> void:
	if not registry.has(id) or id == active_tool_id:
		return

	# Switching mid-gesture would strand the outgoing tool holding a half-drawn
	# stroke, so cancel it first.
	var current: PPTool = get_tool()
	if current != null and current.is_active():
		current.cancel(context)

	active_tool_id = id
	tool_changed.emit(get_tool())


func set_playing(value: bool) -> void:
	if playing == value:
		return
	playing = value
	_playback_elapsed = 0.0
	playback_changed.emit(playing)


func toggle_playing() -> void:
	set_playing(not playing)


func _on_status(text: String) -> void:
	status_message.emit(text)


# --- Convenience actions bound to menus and shortcuts ------------------------

func undo() -> void:
	if document != null:
		document.history.undo()


func redo() -> void:
	if document != null:
		document.history.redo()


func can_undo() -> bool:
	return document != null and document.history.can_undo()


func can_redo() -> bool:
	return document != null and document.history.can_redo()
