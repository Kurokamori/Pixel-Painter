class_name PPToolRegistry
extends RefCounted

## Owns one instance of every tool and hands them out by id.
##
## Tools are stateful mid-gesture, so they are instantiated once and reused
## rather than constructed per press -- which also means switching tools while a
## gesture is running can cleanly cancel the outgoing one.

var _tools: Dictionary[StringName, PPTool] = {}
var _order: Array[StringName] = []


func _init() -> void:
	_register(PPToolPencil.new())
	_register(PPToolEraser.new())
	_register(PPToolBucket.new())
	_register(PPToolEyedropper.new())
	_register(PPToolLine.new())
	_register(PPToolRectangle.new())
	_register(PPToolEllipse.new())
	_register(PPToolGradient.new())
	_register(PPToolSelectRect.new())
	_register(PPToolSelectEllipse.new())
	_register(PPToolLasso.new())
	_register(PPToolMagicWand.new())
	_register(PPToolMove.new())


func _register(tool: PPTool) -> void:
	_tools[tool.get_id()] = tool
	_order.append(tool.get_id())


func get_tool(id: StringName) -> PPTool:
	return _tools.get(id, null)


func get_ids() -> Array[StringName]:
	return _order


func has(id: StringName) -> bool:
	return _tools.has(id)
