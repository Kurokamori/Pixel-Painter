extends SceneTree

## Boots the real editor scene, draws a few frames, and saves a screenshot.
##
##   godot --path . --script tools/screenshot.gd -- <output.png>
##
## Used to check that the UI actually composes and renders -- a project can parse
## and import perfectly while still coming up as an empty grey rectangle.

const WARMUP_FRAMES: int = 30


func _initialize() -> void:
	root.set_content_scale_size(Vector2i(1600, 1000))

	var scene: PackedScene = load("res://src/ui/app_root.tscn")
	if scene == null:
		print("FAIL: could not load app_root.tscn")
		quit(1)
		return

	var app: Node = scene.instantiate()
	if app == null:
		print("FAIL: could not instantiate app_root.tscn")
		quit(1)
		return

	root.add_child(app)
	_capture(app)


func _capture(app: Node) -> void:
	var output: String = "user://screenshot.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		output = args[0]

	# Let the UI lay out, the canvas zoom-to-fit, and the first composite land.
	for i: int in range(WARMUP_FRAMES):
		await process_frame

	# Draw something, so the screenshot proves the paint path works end to end
	# and not merely that the chrome renders.
	var state: PPAppState = app.get_node("%AppState") as PPAppState
	if state != null and state.document != null:
		_paint_demo(state)
		for i: int in range(6):
			await process_frame

	await process_frame
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(output)
	if error != OK:
		print("FAIL: could not save screenshot (error %d)" % error)
		quit(1)
		return

	print("OK: wrote %s (%d x %d)" % [output, image.get_width(), image.get_height()])
	quit(0)


## Drives the real tools through the real context -- the same code path the
## canvas uses when a pen touches the screen.
func _paint_demo(state: PPAppState) -> void:
	var settings: PPToolSettings = state.settings
	var context: PPToolContext = state.context

	settings.primary_color = Color8(232, 59, 68, 255)
	settings.brush_size = 2

	var pencil: PPTool = state.registry.get_tool(&"pencil")
	_stroke(pencil, context, [Vector2(12, 40), Vector2(20, 20), Vector2(32, 34), Vector2(44, 14)])

	settings.primary_color = Color8(99, 199, 77, 255)
	settings.shape_filled = true
	var ellipse: PPTool = state.registry.get_tool(&"ellipse")
	_stroke(ellipse, context, [Vector2(34, 40), Vector2(56, 58)])

	settings.primary_color = Color8(41, 173, 255, 255)
	var rect: PPTool = state.registry.get_tool(&"rectangle")
	_stroke(rect, context, [Vector2(6, 48), Vector2(26, 60)])


func _stroke(tool: PPTool, context: PPToolContext, points: Array) -> void:
	for i: int in range(points.size()):
		var pointer: PPPointer = PPPointer.new()
		pointer.position = points[i]
		if i == 0:
			tool.press(context, pointer)
		else:
			tool.drag(context, pointer)

	var last: PPPointer = PPPointer.new()
	last.position = points[points.size() - 1]
	tool.release(context, last)
