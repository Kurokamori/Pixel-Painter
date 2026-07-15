class_name PPToolsPanel
extends PanelContainer

## The tool rack.
##
## The buttons live in the scene, not in code -- each carries a `tool_id` in its
## metadata, which is the only thing binding it to a PPTool. Adding a tool means
## registering it in PPToolRegistry and dropping a button in the scene; no code
## here changes.

var app: PPAppState = null

@onready var _tools: VBoxContainer = %Tools


func bind(state: PPAppState) -> void:
	app = state
	app.tool_changed.connect(_on_tool_changed)

	for child: Node in _tools.get_children():
		var button: Button = child as Button
		if button == null or not button.has_meta("tool_id"):
			continue
		button.pressed.connect(_on_pressed.bind(button))

	_sync(app.active_tool_id)


func _on_pressed(button: Button) -> void:
	app.set_tool(StringName(button.get_meta("tool_id")))


func _on_tool_changed(tool: PPTool) -> void:
	_sync(tool.get_id())


## Reflects the active tool back into the buttons, so a tool chosen by keyboard
## shortcut lights up its button too.
func _sync(id: StringName) -> void:
	for child: Node in _tools.get_children():
		var button: Button = child as Button
		if button == null or not button.has_meta("tool_id"):
			continue
		var matches: bool = StringName(button.get_meta("tool_id")) == id
		if button.button_pressed != matches:
			button.set_pressed_no_signal(matches)
