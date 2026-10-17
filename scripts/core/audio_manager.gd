extends Node
## Plays music, room ambience and sound effects on the Music, Ambience and SFX
## buses (volumes come from Settings). Loops crossfade when they change.

const SFX_DIR := "res://assets/audio/sfx/"
const FADE_SECONDS := 1.5
const SILENT_DB := -40.0
const SFX_VOICES := 6

var _music: Array[AudioStreamPlayer] = []
var _ambience: Array[AudioStreamPlayer] = []
var _sfx: Array[AudioStreamPlayer] = []
var _current := {"Music": "", "Ambience": ""}


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	for i in 2:
		_music.append(_make_player("Music"))
		_ambience.append(_make_player("Ambience"))
	for i in SFX_VOICES:
		_sfx.append(_make_player("SFX"))


## Plays res://assets/audio/sfx/<id>.wav.
func play_sfx(id: String) -> void:
	var path := SFX_DIR + id + ".wav"
	if not ResourceLoader.exists(path):
		push_warning("[Audio] Missing sound effect %s." % path)
		return
	var player := _sfx[0]
	for candidate in _sfx:
		if not candidate.playing:
			player = candidate
			break
	player.stream = load(path)
	player.play()


func set_music(path: String) -> void:
	_crossfade(_music, "Music", path)


func set_ambience(path: String) -> void:
	_crossfade(_ambience, "Ambience", path)


func sfx_exists(id: String) -> bool:
	return ResourceLoader.exists(SFX_DIR + id + ".wav")


func _crossfade(pair: Array[AudioStreamPlayer], bus: String, path: String) -> void:
	if _current[bus] == path:
		return
	_current[bus] = path
	var old := pair[0] if pair[0].playing else pair[1]
	var new := pair[1] if old == pair[0] else pair[0]
	if old.playing:
		var fade_out := create_tween()
		fade_out.tween_property(old, "volume_db", SILENT_DB, FADE_SECONDS)
		fade_out.tween_callback(old.stop)
	if path == "" or not ResourceLoader.exists(path):
		return
	new.stream = _looping(load(path))
	new.volume_db = SILENT_DB
	new.play()
	create_tween().tween_property(new, "volume_db", 0.0, FADE_SECONDS)


func _looping(stream: AudioStream) -> AudioStream:
	var wav := stream as AudioStreamWAV
	if wav:
		var frames: int = wav.data.size() / (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1)
		if wav.stereo:
			frames /= 2
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = frames
	return stream


func _make_player(bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player
