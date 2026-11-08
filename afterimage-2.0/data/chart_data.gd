class_name ChartData
extends Resource

var title: String = ""
var artist: String = "Unknown artist"
var difficulty: String = "Custom"
var source_path: String = ""
var song_path: String = ""
var bpm: float = 120.0
var offset: float = 0.0
var notes: Array[NoteData] = []
var audio: AudioStream
var album: AlbumData

func last_time() -> float:
	var result: float = 0.0
	for note: NoteData in notes:
		result = maxf(result, note.end_time())
	return result
