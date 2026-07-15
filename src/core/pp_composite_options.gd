class_name PPCompositeOptions
extends RefCounted

## Knobs for a single compositing pass. Kept as an object rather than a long
## argument list because almost every call site cares about a different subset.

## While a shape/line tool is dragging, its in-progress pixels live in a scratch
## buffer instead of the cel. Setting these substitutes that buffer for the
## layer's real cel for the duration of the pass, giving a live preview with no
## destructive write and no undo entry.
var override_layer_index: int = -1
var override_image: Image = null

## Skips a layer entirely -- used when the move tool has lifted a selection's
## pixels out of the cel and is drawing them as a floating overlay instead.
var skip_layer_index: int = -1

## When false, hidden layers are composited anyway. Exporters use the default
## (true); the "flatten visible" command also uses it.
var only_visible: bool = true

## Reference layers are on-canvas guides. They are shown while editing but are
## excluded from every flattened export.
var include_reference: bool = true


static func for_export() -> PPCompositeOptions:
	var options: PPCompositeOptions = PPCompositeOptions.new()
	options.only_visible = true
	options.include_reference = false
	return options
