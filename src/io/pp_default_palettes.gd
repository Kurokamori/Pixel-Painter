@abstract
class_name PPDefaultPalettes
extends RefCounted

## Palettes bundled with the app so a new sprite is never staring at an empty
## swatch rack. These are the published, canonical colour values for each
## palette -- they are widely used and artists notice when they are wrong.

const DB32: Array[String] = [
	"000000", "222034", "45283C", "663931", "8F563B", "DF7126", "D9A066", "EEC39A",
	"FBF236", "99E550", "6ABE30", "37946E", "4B692F", "524B24", "323C39", "3F3F74",
	"306082", "5B6EE1", "639BFF", "5FCDE4", "CBDBFC", "FFFFFF", "9BADB7", "847E87",
	"696A6A", "595652", "76428A", "AC3232", "D95763", "D77BBA", "8F974A", "8A6F30",
]

const PICO_8: Array[String] = [
	"000000", "1D2B53", "7E2553", "008751", "AB5236", "5F574F", "C2C3C7", "FFF1E8",
	"FF004D", "FFA300", "FFEC27", "00E436", "29ADFF", "83769C", "FF77A8", "FFCCAA",
]

const ENDESGA_32: Array[String] = [
	"BE4A2F", "D77643", "EAD4AA", "E4A672", "B86F50", "733E39", "3E2731", "A22633",
	"E43B44", "F77622", "FEAE34", "FEE761", "63C74D", "3E8948", "265C42", "193C3E",
	"124E89", "0099DB", "2CE8F5", "FFFFFF", "C0CBDC", "8B9BB4", "5A6988", "3A4466",
	"262B44", "181425", "FF0044", "68386C", "B55088", "F6757A", "E8B796", "C28569",
]

const SWEETIE_16: Array[String] = [
	"1A1C2C", "5D275D", "B13E53", "EF7D57", "FFCD75", "A7F070", "38B764", "257179",
	"29366F", "3B5DC9", "41A6F6", "73EFF7", "F4F4F4", "94B0C2", "566C86", "333C57",
]

const RESURRECT_64: Array[String] = [
	"2E222F", "3E3546", "625565", "966C6C", "AB947A", "694F62", "7F708A", "9BA0EF",
	"C7DCD0", "FFFFFF", "6E2727", "B33831", "EA4F36", "F57D4A", "AE2334", "E83B3B",
	"FB6B1D", "F79617", "F9C22B", "7A3045", "9E4539", "CD683D", "E6904E", "FBB954",
	"4C3E24", "676633", "A2A947", "D5E04B", "FBFF86", "165A4C", "239063", "1EBC73",
	"91DB69", "CDDF6C", "313638", "374E4A", "547E64", "92A984", "B2BA90", "0B5E65",
	"0B8A8F", "0EAF9B", "30E1B9", "8FF8E2", "323353", "484A77", "4D65B4", "4D9BE6",
	"8FD3FF", "45293F", "6B3E75", "905EA9", "A884F3", "EAADED", "753C54", "A24B6F",
	"CF657F", "ED8099", "831C5D", "C32454", "F04F78", "F68181", "FCA790", "FDCBB0",
]

const AAP_64: Array[String] = [
	"060608", "141013", "3B1725", "73172D", "B4202A", "DF3E23", "FA6A0A", "F9A31B",
	"FFD541", "FFFC40", "D6F264", "9CDB43", "59C135", "14A02E", "1A7A3E", "24523B",
	"122020", "143464", "285CC4", "249FDE", "20D6C7", "A6FCDB", "FFFFFF", "FEF3C0",
	"FAD6B8", "F5A097", "E86A73", "BC4A9B", "793A80", "403353", "242234", "221C1A",
	"322B28", "71413B", "BB7547", "DBA463", "F4D29C", "DAE0EA", "B3B9D1", "8B93AF",
	"6D758D", "4A5462", "333941", "422433", "5B3138", "8E5252", "BA756A", "E9B5A3",
	"E3E6FF", "B9BFFB", "849BE4", "588DBE", "477D85", "23674E", "328464", "5DAF8D",
	"92DCBA", "CDF7E2", "E4D2AA", "C7B08B", "A08662", "796755", "5A4E44", "423934",
]

## The NES master palette. The console's 64 slots include four duplicate blacks
## and two unusable "blacker than black" entries; this is the 54 distinct
## displayable colours, which is what artists actually work with.
const NES: Array[String] = [
	"7C7C7C", "0000FC", "0000BC", "4428BC", "940084", "A80020", "A81000", "881400",
	"503000", "007800", "006800", "005800", "004058", "000000", "BCBCBC", "0078F8",
	"0058F8", "6844FC", "D800CC", "E40058", "F83800", "E45C10", "AC7C00", "00B800",
	"00A800", "00A844", "008888", "F8F8F8", "3CBCFC", "6888FC", "9878F8", "F878F8",
	"F85898", "F87858", "FCA044", "F8B800", "B8F818", "58D854", "58F898", "00E8D8",
	"787878", "FCFCFC", "A4E4FC", "B8B8F8", "D8B8F8", "F8B8F8", "F8A4C0", "F0D0B0",
	"FCE0A8", "F8D878", "D8F878", "B8F8B8", "B8F8D8", "00FCFC", "F8D8F8",
]


static func get_names() -> PackedStringArray:
	return PackedStringArray(
		[
			"DB32",
			"PICO-8",
			"Endesga 32",
			"Sweetie 16",
			"Resurrect 64",
			"AAP-64",
			"NES",
			"Grayscale 16",
		]
	)


## A fresh copy every call -- palettes are mutable, and handing out a shared
## instance would let one sprite's edits leak into the next.
static func get_palette(name: String) -> PPPalette:
	match name:
		"DB32":
			return _build("DB32", DB32)
		"PICO-8":
			return _build("PICO-8", PICO_8)
		"Endesga 32":
			return _build("Endesga 32", ENDESGA_32)
		"Sweetie 16":
			return _build("Sweetie 16", SWEETIE_16)
		"Resurrect 64":
			return _build("Resurrect 64", RESURRECT_64)
		"AAP-64":
			return _build("AAP-64", AAP_64)
		"NES":
			return _build("NES", NES)
		"Grayscale 16":
			return _build_grayscale(16)
	return null


static func get_default() -> PPPalette:
	return _build("DB32", DB32)


static func _build(name: String, hex_values: Array[String]) -> PPPalette:
	var colors: PackedColorArray = PackedColorArray()
	for hex: String in hex_values:
		var color: Color = PPPaletteIO.parse_hex(hex)
		if color.a >= 0.0:
			colors.append(color)
	return PPPalette.create(name, colors)


static func _build_grayscale(steps: int) -> PPPalette:
	var colors: PackedColorArray = PackedColorArray()
	for i: int in range(steps):
		var value: float = float(i) / float(steps - 1)
		colors.append(Color(value, value, value, 1.0))
	return PPPalette.create("Grayscale %d" % steps, colors)
