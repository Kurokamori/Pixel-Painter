class_name PPToolOptionsBar
extends PanelContainer

## Context bar for the active tool.
##
## Every control exists in the scene; the bar simply shows the ones the tool
## declares it honours via PPTool.get_options(). A tool can therefore never
## display a knob it silently ignores -- the option list *is* the contract.

var app: PPAppState = null

@onready var _tool_name: Label = %ToolNameLabel

@onready var _brush_group: HBoxContainer = %BrushGroup
@onready var _brush_shape: OptionButton = %BrushShapeOption
@onready var _brush_size: SpinBox = %BrushSizeSpin

@onready var _opacity_group: HBoxContainer = %OpacityGroup
@onready var _opacity: HSlider = %OpacitySlider
@onready var _opacity_value: Label = %OpacityValueLabel

@onready var _pixel_perfect_group: HBoxContainer = %PixelPerfectGroup
@onready var _pixel_perfect: CheckButton = %PixelPerfectCheck

@onready var _lock_alpha_group: HBoxContainer = %LockAlphaGroup
@onready var _lock_alpha: CheckButton = %LockAlphaCheck

@onready var _tolerance_group: HBoxContainer = %ToleranceGroup
@onready var _tolerance: SpinBox = %ToleranceSpin

@onready var _contiguous_group: HBoxContainer = %ContiguousGroup
@onready var _contiguous: CheckButton = %ContiguousCheck

@onready var _sample_group: HBoxContainer = %SampleGroup
@onready var _sample_all: CheckButton = %SampleAllCheck

@onready var _fill_group: HBoxContainer = %FillGroup
@onready var _fill: CheckButton = %FillCheck

@onready var _from_center_group: HBoxContainer = %FromCenterGroup
@onready var _from_center: CheckButton = %FromCenterCheck

@onready var _selection_op_group: HBoxContainer = %SelectionOpGroup
@onready var _selection_op: OptionButton = %SelectionOpOption

@onready var _symmetry_group: HBoxContainer = %SymmetryGroup
@onready var _symmetry: OptionButton = %SymmetryOption

@onready var _pressure_group: HBoxContainer = %PressureGroup
@onready var _pressure: OptionButton = %PressureOption


func bind(state: PPAppState) -> void:
	app = state
	app.tool_changed.connect(_on_tool_changed)

	_populate_choices()
	_load_from_settings()
	_connect_controls()
	_on_tool_changed(app.get_tool())


func _populate_choices() -> void:
	_brush_shape.clear()
	_brush_shape.add_item("Circle", int(PPTypes.BrushShape.CIRCLE))
	_brush_shape.add_item("Square", int(PPTypes.BrushShape.SQUARE))
	_brush_shape.add_item("Diamond", int(PPTypes.BrushShape.DIAMOND))

	_selection_op.clear()
	_selection_op.add_item("Replace", int(PPTypes.SelectionOp.REPLACE))
	_selection_op.add_item("Add", int(PPTypes.SelectionOp.ADD))
	_selection_op.add_item("Subtract", int(PPTypes.SelectionOp.SUBTRACT))
	_selection_op.add_item("Intersect", int(PPTypes.SelectionOp.INTERSECT))

	_symmetry.clear()
	_symmetry.add_item("None", int(PPTypes.SymmetryMode.NONE))
	_symmetry.add_item("Horizontal", int(PPTypes.SymmetryMode.HORIZONTAL))
	_symmetry.add_item("Vertical", int(PPTypes.SymmetryMode.VERTICAL))
	_symmetry.add_item("Both", int(PPTypes.SymmetryMode.BOTH))

	_pressure.clear()
	_pressure.add_item("Ignore", int(PPTypes.PressureTarget.NONE))
	_pressure.add_item("Size", int(PPTypes.PressureTarget.SIZE))
	_pressure.add_item("Opacity", int(PPTypes.PressureTarget.OPACITY))
	_pressure.add_item("Size + Opacity", int(PPTypes.PressureTarget.SIZE_AND_OPACITY))


func _load_from_settings() -> void:
	var settings: PPToolSettings = app.settings
	_brush_shape.select(_brush_shape.get_item_index(int(settings.brush_shape)))
	_brush_size.value = settings.brush_size
	_opacity.value = settings.opacity * 100.0
	_opacity_value.text = "%d%%" % int(settings.opacity * 100.0)
	_pixel_perfect.button_pressed = settings.pixel_perfect
	_lock_alpha.button_pressed = settings.lock_alpha
	_tolerance.value = settings.tolerance
	_contiguous.button_pressed = settings.contiguous
	_sample_all.button_pressed = settings.sample_all_layers
	_fill.button_pressed = settings.shape_filled
	_from_center.button_pressed = settings.shape_from_center
	_selection_op.select(_selection_op.get_item_index(int(settings.selection_op)))
	_symmetry.select(_symmetry.get_item_index(int(settings.symmetry)))
	_pressure.select(_pressure.get_item_index(int(settings.pressure_target)))


func _connect_controls() -> void:
	var settings: PPToolSettings = app.settings

	_brush_shape.item_selected.connect(
		func(index: int) -> void:
			settings.brush_shape = _brush_shape.get_item_id(index) as PPTypes.BrushShape
			settings.notify_changed()
	)
	_brush_size.value_changed.connect(
		func(value: float) -> void:
			settings.set_brush_size(int(value))
			_refresh_pixel_perfect_enabled()
	)
	_opacity.value_changed.connect(
		func(value: float) -> void:
			settings.opacity = clampf(value / 100.0, 0.0, 1.0)
			_opacity_value.text = "%d%%" % int(value)
			settings.notify_changed()
	)
	_pixel_perfect.toggled.connect(
		func(on: bool) -> void:
			settings.pixel_perfect = on
			settings.notify_changed()
	)
	_lock_alpha.toggled.connect(
		func(on: bool) -> void:
			settings.lock_alpha = on
			settings.notify_changed()
	)
	_tolerance.value_changed.connect(
		func(value: float) -> void:
			settings.tolerance = int(value)
			settings.notify_changed()
	)
	_contiguous.toggled.connect(
		func(on: bool) -> void:
			settings.contiguous = on
			settings.notify_changed()
	)
	_sample_all.toggled.connect(
		func(on: bool) -> void:
			settings.sample_all_layers = on
			settings.notify_changed()
	)
	_fill.toggled.connect(
		func(on: bool) -> void:
			settings.shape_filled = on
			settings.notify_changed()
	)
	_from_center.toggled.connect(
		func(on: bool) -> void:
			settings.shape_from_center = on
			settings.notify_changed()
	)
	_selection_op.item_selected.connect(
		func(index: int) -> void:
			settings.selection_op = (
				_selection_op.get_item_id(index) as PPTypes.SelectionOp
			)
			settings.notify_changed()
	)
	_symmetry.item_selected.connect(
		func(index: int) -> void:
			settings.symmetry = _symmetry.get_item_id(index) as PPTypes.SymmetryMode
			settings.notify_changed()
	)
	_pressure.item_selected.connect(
		func(index: int) -> void:
			settings.pressure_target = (
				_pressure.get_item_id(index) as PPTypes.PressureTarget
			)
			settings.notify_changed()
	)


func _on_tool_changed(tool: PPTool) -> void:
	if tool == null:
		return
	_tool_name.text = tool.get_display_name()

	var options: Array[PPTool.Option] = tool.get_options()
	_brush_group.visible = options.has(PPTool.Option.BRUSH)
	_opacity_group.visible = options.has(PPTool.Option.OPACITY)
	_pixel_perfect_group.visible = options.has(PPTool.Option.PIXEL_PERFECT)
	_lock_alpha_group.visible = options.has(PPTool.Option.LOCK_ALPHA)
	_tolerance_group.visible = options.has(PPTool.Option.TOLERANCE)
	_contiguous_group.visible = options.has(PPTool.Option.CONTIGUOUS)
	_sample_group.visible = options.has(PPTool.Option.SAMPLE_ALL_LAYERS)
	_fill_group.visible = options.has(PPTool.Option.SHAPE_FILL)
	_from_center_group.visible = options.has(PPTool.Option.SHAPE_FROM_CENTER)
	_selection_op_group.visible = options.has(PPTool.Option.SELECTION_OP)
	_symmetry_group.visible = options.has(PPTool.Option.SYMMETRY)
	_pressure_group.visible = options.has(PPTool.Option.PRESSURE)

	_refresh_pixel_perfect_enabled()


## Pixel-perfect only has meaning for a 1px brush -- a wider dab already covers
## the corner it would remove. Rather than silently ignore the setting, grey it
## out and say so.
func _refresh_pixel_perfect_enabled() -> void:
	var applies: bool = app.settings.brush_size == 1
	_pixel_perfect.disabled = not applies
	if applies:
		_pixel_perfect.tooltip_text = (
			"Removes redundant corner pixels from freehand strokes."
		)
	else:
		_pixel_perfect.tooltip_text = (
			"Only applies to a 1px brush -- a wider brush already covers the corner."
		)
