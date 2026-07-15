class_name PPCompositeCommand
extends PPCommand

## Groups several commands into one undo step.
##
## Needed whenever a single user gesture spans more than one cel or mixes pixel
## and structural work -- painting across a multi-frame selection, "delete
## selection" (pixels + selection mask), or a paste (pixels + new layer).

var _commands: Array[PPCommand] = []


static func create(commands: Array[PPCommand], label_text: String) -> PPCommand:
	var kept: Array[PPCommand] = []
	for command: PPCommand in commands:
		if command != null:
			kept.append(command)
	if kept.is_empty():
		return null
	if kept.size() == 1:
		kept[0].label = label_text
		return kept[0]

	var composite: PPCompositeCommand = PPCompositeCommand.new()
	composite.label = label_text
	composite._commands = kept
	return composite


func redo(document: PPDocument) -> void:
	for command: PPCommand in _commands:
		command.redo(document)


func undo(document: PPDocument) -> void:
	# Unwinding must run in reverse: a later command may depend on state an
	# earlier one established.
	for i: int in range(_commands.size() - 1, -1, -1):
		_commands[i].undo(document)


func is_structural() -> bool:
	for command: PPCommand in _commands:
		if command.is_structural():
			return true
	return false


func get_dirty_rect(document: PPDocument) -> Rect2i:
	var union: Rect2i = Rect2i()
	var first: bool = true
	for command: PPCommand in _commands:
		var rect: Rect2i = command.get_dirty_rect(document)
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		if first:
			union = rect
			first = false
		else:
			union = union.merge(rect)
	if first:
		return document.sprite.get_bounds()
	return union


func get_commands() -> Array[PPCommand]:
	return _commands
