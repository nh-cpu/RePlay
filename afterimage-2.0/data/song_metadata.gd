class_name SongMetadata
extends Resource

@export var id: String = ""
@export var title: String = ""
@export var artist: String = ""
@export var artwork_path: String = ""
@export var artwork_candidates: PackedStringArray = []
@export var difficulties: Array[SongDifficultyMetadata] = []
