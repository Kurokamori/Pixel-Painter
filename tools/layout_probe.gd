extends SceneTree

## Prints the laid-out rect and minimum size of every significant UI node.
##
##   godot --path . --script tools/layout_probe.gd
##
## A screenshot tells you the layout is wrong; this tells you which node is
## demanding the space.

const PATHS: Array[String] = [
	"Main",
	"Main/TopBar",
	"Main/ToolOptionsBar",
	"Main/Middle",
	"Main/Middle/ToolsPanel",
	"Main/Middle/CanvasView",
	"Main/Middle/RightDock",
	"Main/Middle/RightDock/ColorPanel",
	"Main/Middle/RightDock/PalettePanel",
	"Main/Middle/RightDock/LayersPanel",
	"Main/TimelinePanel",
]


func _initialize() -> void:
	var scene: PackedScene = load("res://src/ui/app_root.tscn")
	var app: Control = scene.instantiate() as Control
	root.add_child(app)

	for i: int in range(20):
		await process_frame

	print("viewport = ", root.size)
	print("app rect = ", app.get_rect(), "  min = ", app.get_combined_minimum_size())
	print("")

	for path: String in PATHS:
		var node: Control = app.get_node_or_null(path) as Control
		if node == null:
			print("%-42s MISSING" % path)
			continue
		print(
			"%-42s rect=%-28s min=%s"
			% [path, str(node.get_rect()), str(node.get_combined_minimum_size())]
		)

	# The colour picker is the usual suspect for an immovable minimum height.
	var picker: Control = app.get_node_or_null(
		"Main/Middle/RightDock/ColorPanel/Layout/Picker"
	) as Control
	if picker != null:
		print("")
		print("ColorPicker min = ", picker.get_combined_minimum_size())

	quit(0)
