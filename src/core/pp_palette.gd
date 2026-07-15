class_name PPPalette
extends Resource

## An ordered list of swatches. Colours are stored straight (non-premultiplied)
## and may carry alpha, so palettes can describe transparent entries.

## Named `palette_changed` rather than `changed`: Resource already defines a
## `changed` signal, and shadowing it is a parse error.
signal palette_changed()

@export var name: String = "Palette"
@export var colors: PackedColorArray = PackedColorArray()

## Optional per-swatch names, sparse: index -> name. Preserved across .gpl I/O.
@export var color_names: Dictionary[int, String] = {}


static func create(palette_name: String, palette_colors: PackedColorArray) -> PPPalette:
	var palette: PPPalette = PPPalette.new()
	palette.name = palette_name
	palette.colors = palette_colors.duplicate()
	return palette


func size() -> int:
	return colors.size()


func get_color(index: int) -> Color:
	if index < 0 or index >= colors.size():
		return Color(0.0, 0.0, 0.0, 0.0)
	return colors[index]


func set_color(index: int, color: Color) -> void:
	if index < 0 or index >= colors.size():
		return
	colors[index] = color
	palette_changed.emit()


func add_color(color: Color) -> int:
	colors.append(color)
	palette_changed.emit()
	return colors.size() - 1


func insert_color(index: int, color: Color) -> void:
	var target: int = clampi(index, 0, colors.size())
	colors.insert(target, color)
	_shift_names(target, 1)
	palette_changed.emit()


func remove_color(index: int) -> void:
	if index < 0 or index >= colors.size():
		return
	colors.remove_at(index)
	color_names.erase(index)
	_shift_names(index, -1)
	palette_changed.emit()


func move_color(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= colors.size():
		return
	var target: int = clampi(to_index, 0, colors.size() - 1)
	if target == from_index:
		return
	var color: Color = colors[from_index]
	colors.remove_at(from_index)
	colors.insert(target, color)
	palette_changed.emit()


## Index of an exact colour match, or -1.
func find_color(color: Color) -> int:
	for i: int in range(colors.size()):
		if colors[i].is_equal_approx(color):
			return i
	return -1


## Index of the perceptually nearest swatch, or -1 for an empty palette.
## Distance is weighted RGB, which tracks human colour perception far better
## than a raw euclidean distance for the small palettes pixel art uses.
func find_nearest(color: Color) -> int:
	if colors.is_empty():
		return -1
	var best_index: int = 0
	var best_distance: float = INF
	for i: int in range(colors.size()):
		var candidate: Color = colors[i]
		var mean_r: float = (candidate.r + color.r) * 0.5
		var dr: float = candidate.r - color.r
		var dg: float = candidate.g - color.g
		var db: float = candidate.b - color.b
		var da: float = candidate.a - color.a
		var distance: float = (
			(2.0 + mean_r) * dr * dr
			+ 4.0 * dg * dg
			+ (3.0 - mean_r) * db * db
			+ 4.0 * da * da
		)
		if distance < best_distance:
			best_distance = distance
			best_index = i
	return best_index


func get_color_name(index: int) -> String:
	return color_names.get(index, "")


func set_color_name(index: int, color_name: String) -> void:
	if color_name.is_empty():
		color_names.erase(index)
	else:
		color_names[index] = color_name


func sort_by_luminance() -> void:
	var list: Array[Color] = []
	for color: Color in colors:
		list.append(color)
	list.sort_custom(
		func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance()
	)
	colors = PackedColorArray(list)
	color_names.clear()
	palette_changed.emit()


func duplicate_palette() -> PPPalette:
	var copy: PPPalette = PPPalette.new()
	copy.name = name
	copy.colors = colors.duplicate()
	copy.color_names = color_names.duplicate()
	return copy


func _shift_names(from_index: int, delta: int) -> void:
	var rebuilt: Dictionary[int, String] = {}
	for key: int in color_names:
		if key >= from_index:
			rebuilt[key + delta] = color_names[key]
		else:
			rebuilt[key] = color_names[key]
	color_names = rebuilt
