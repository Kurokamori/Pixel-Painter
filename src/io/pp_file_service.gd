@abstract
class_name PPFileService
extends RefCounted

## One front door for opening and saving documents, dispatching on extension.
##
## Keeping this in one place means the UI, the sync layer and the tests all agree
## on which extensions are openable and which are lossy on save -- a .png "save"
## silently discarding every layer would otherwise be very easy to ship.


static func open_extensions() -> PackedStringArray:
	var extensions: PackedStringArray = PackedStringArray([PPProjectIO.EXTENSION])
	extensions.append_array(PPAseIO.supported_extensions())
	extensions.append("png")
	return extensions


static func open_filters() -> PackedStringArray:
	return PackedStringArray(
		[
			"*.pxp;Pixel Painter Project",
			"*.ase,*.aseprite;Aseprite Sprite",
			"*.png;PNG Image",
		]
	)


static func save_filters() -> PackedStringArray:
	return PackedStringArray(
		[
			"*.pxp;Pixel Painter Project",
			"*.ase,*.aseprite;Aseprite Sprite",
		]
	)


## True when saving to this extension would throw away layers, frames or tags.
static func is_lossy(path: String) -> bool:
	var extension: String = path.get_extension().to_lower()
	return extension == "png" or extension == "gif"


static func open(path: String) -> PPDocument:
	var extension: String = path.get_extension().to_lower()
	match extension:
		PPProjectIO.EXTENSION:
			return PPProjectIO.load_project(path)
		"ase", "aseprite":
			return PPAseIO.load_ase(path)
		"png":
			return PPExportIO.import_image(path)
	return null


## Saves in the document's own format. PNG/GIF are exports, not saves, and are
## refused here so that "Save" can never quietly flatten someone's work.
static func save(document: PPDocument, path: String) -> Error:
	var extension: String = path.get_extension().to_lower()
	match extension:
		PPProjectIO.EXTENSION:
			var project_error: Error = PPProjectIO.save(document, path)
			if project_error == OK:
				document.mark_saved(path)
			return project_error
		"ase", "aseprite":
			var ase_error: Error = PPAseIO.save(document, path)
			if ase_error == OK:
				document.mark_saved(path)
			return ase_error
	return ERR_FILE_UNRECOGNIZED


## Appends the default extension when the user typed a bare name.
static func ensure_extension(path: String, fallback: String = PPProjectIO.EXTENSION) -> String:
	if path.get_extension().is_empty():
		return "%s.%s" % [path, fallback]
	return path
