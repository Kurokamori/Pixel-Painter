class_name PPHistory
extends RefCounted

## Linear undo/redo stack.
##
## Pushing a command *executes* it, so callers never apply an edit and record it
## separately -- there is exactly one path by which the document changes, which
## is what keeps undo trustworthy.

signal changed()

const DEFAULT_LIMIT: int = 128

var limit: int = DEFAULT_LIMIT

var _document: PPDocument = null
var _undo_stack: Array[PPCommand] = []
var _redo_stack: Array[PPCommand] = []

## Depth counter for begin_group()/end_group(); commands pushed inside a group
## are collected and committed as a single undo step.
var _group_depth: int = 0
var _group_buffer: Array[PPCommand] = []
var _group_label: String = ""

## Set while undo()/redo() is running so that document signal handlers can tell
## a user edit apart from a history replay.
var _replaying: bool = false


func _init(document: PPDocument) -> void:
	_document = document


func is_replaying() -> bool:
	return _replaying


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func undo_label() -> String:
	if _undo_stack.is_empty():
		return ""
	return _undo_stack[-1].label


func redo_label() -> String:
	if _redo_stack.is_empty():
		return ""
	return _redo_stack[-1].label


## Executes `command` and records it. Null is accepted and ignored, so callers
## can pass a factory result straight through without a no-op check -- the
## command factories return null precisely when there is nothing to do.
func push(command: PPCommand) -> void:
	if command == null:
		return

	if _group_depth > 0:
		command.redo(_document)
		_group_buffer.append(command)
		_document.notify_command_applied(command)
		return

	command.redo(_document)
	_document.notify_command_applied(command)

	if not _undo_stack.is_empty() and _undo_stack[-1].merge_with(command):
		_redo_stack.clear()
		changed.emit()
		return

	_undo_stack.append(command)
	_redo_stack.clear()
	_trim()
	changed.emit()


## Records a command whose effect the caller has *already* applied. Used by the
## painting tools, which mutate the cel live during a drag for responsiveness
## and only hand over the before/after pair when the stroke ends.
##
## The document is still marked dirty here. It is tempting to skip that -- the
## pixels are already on screen, after all -- but "already applied" refers only
## to the *rendering*: without this, painting a stroke and quitting would lose
## the work with no warning, because nothing ever told the document it changed.
func push_applied(command: PPCommand) -> void:
	if command == null:
		return

	_document.set_dirty(true)

	if _group_depth > 0:
		_group_buffer.append(command)
		return

	_undo_stack.append(command)
	_redo_stack.clear()
	_trim()
	changed.emit()


func begin_group(label_text: String) -> void:
	if _group_depth == 0:
		_group_buffer = []
		_group_label = label_text
	_group_depth += 1


func end_group() -> void:
	_group_depth = maxi(0, _group_depth - 1)
	if _group_depth > 0:
		return

	var grouped: PPCommand = PPCompositeCommand.create(_group_buffer, _group_label)
	_group_buffer = []
	if grouped == null:
		return

	_document.set_dirty(true)
	_undo_stack.append(grouped)
	_redo_stack.clear()
	_trim()
	changed.emit()


func undo() -> void:
	if _undo_stack.is_empty():
		return
	var command: PPCommand = _undo_stack.pop_back()

	_replaying = true
	command.undo(_document)
	_replaying = false

	_redo_stack.append(command)
	_document.notify_command_applied(command)
	changed.emit()


func redo() -> void:
	if _redo_stack.is_empty():
		return
	var command: PPCommand = _redo_stack.pop_back()

	_replaying = true
	command.redo(_document)
	_replaying = false

	_undo_stack.append(command)
	_document.notify_command_applied(command)
	changed.emit()


func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_group_buffer.clear()
	_group_depth = 0
	changed.emit()


func _trim() -> void:
	while _undo_stack.size() > limit:
		_undo_stack.remove_at(0)
