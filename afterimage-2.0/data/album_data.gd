class_name AlbumData
extends Resource

var photos: PackedStringArray = []
var cues: Array[Dictionary] = []

static func from_manifest(folder: String, manifest: Dictionary) -> AlbumData:
	var album: AlbumData = AlbumData.new()
	for name: String in manifest.get("photos", []):
		if name.get_file() != name:
			return album
		album.photos.append(folder.path_join(name))
	for value: Variant in manifest.get("cues", []):
		if not value is Dictionary:
			continue
		var cue: Dictionary = value
		if int(cue.get("photo", -1)) >= 0 and int(cue.photo) < album.photos.size() and float(cue.get("end", 0)) > float(cue.get("start", 0)):
			album.cues.append(cue)
	return album
