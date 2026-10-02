extends Node
## Rhubarb phoneme timing, driven by the audio device clock rather than amplitude.

const PHONEMES := {
	"A": "", "B": "ih", "C": "ee", "D": "aa", "E": "oh", "F": "ou", "G": "ee", "H": "ih", "X": ""
}
var performance: Node
var player := AudioStreamPlayer.new()
var cues: Array = []
var duration := 0.0
var last_error := ""
var playback_id: int:
	get:
		return _playback_id
var _playback_id := 0


func _ready() -> void:
	add_child(player)
	process_priority = -1
	player.finished.connect(func(): performance.visemes = {})


func load_clip(path: String) -> bool:
	last_error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 1048576:
		return _fail("无法读取口型时间文件")
	var data: Variant = JSON.parse_string(file.get_as_text())
	if (
		not data is Dictionary
		or not data.get("mouthCues") is Array
		or not data.get("metadata") is Dictionary
	):
		return _fail("需要 Rhubarb JSON 格式")
	var previous := 0.0
	for cue: Variant in data.mouthCues:
		if not _valid_cue(cue, previous):
			return _fail("口型时间段无效或重叠")
		previous = float(cue.end)
	var sound: Variant = data.metadata.get("soundFile", "")
	if not sound is String or sound.get_extension().to_lower() != "wav":
		return _fail("需要配套 WAV 文件")
	# The authoring script stores a basename: a timing file cannot redirect reads.
	var audio_path := path.get_base_dir().path_join(sound.get_file())
	# Project audio is imported by Godot and may be packaged without the raw
	# authoring WAV. Resolve res:// resources through the importer first; keep
	# the filesystem loader for user-selected external WAV files.
	var stream: AudioStream
	if audio_path.begins_with("res://"):
		stream = ResourceLoader.load(audio_path) as AudioStream
	else:
		stream = AudioStreamWAV.load_from_file(audio_path)
	if stream == null or previous > stream.get_length() + 0.1:
		return _fail("配套语音不存在，或时间轴超出音频长度")
	stop()
	player.stream = stream
	cues = data.mouthCues
	duration = stream.get_length()
	return true


func play() -> void:
	if player.stream != null:
		_playback_id += 1
		player.play()


func stop() -> void:
	_playback_id += 1
	player.stop()
	performance.visemes = {}


func sample(time: float) -> Dictionary:
	var result := {}
	for cue: Dictionary in cues:
		if time < cue.start:
			break
		if time >= cue.end:
			continue
		var shape: String = PHONEMES[cue.value]
		if not shape.is_empty():
			var ramp := minf(0.04, (cue.end - cue.start) * 0.25)
			result[shape] = (
				smoothstep(0.0, ramp, time - cue.start) * smoothstep(0.0, ramp, cue.end - time)
			)
		break
	return result


func _process(_delta: float) -> void:
	if not player.playing or player.stream_paused:
		return
	var time := player.get_playback_position() + AudioServer.get_time_since_last_mix()
	time = maxf(0.0, time - AudioServer.get_output_latency())
	performance.visemes = sample(time)


func _valid_cue(cue: Variant, previous: float) -> bool:
	if not cue is Dictionary or not cue.has_all(["start", "end", "value"]):
		return false
	if not (cue.start is float or cue.start is int) or not (cue.end is float or cue.end is int):
		return false
	return (
		is_finite(cue.start)
		and is_finite(cue.end)
		and cue.start >= previous
		and cue.end > cue.start
		and cue.value is String
		and PHONEMES.has(cue.value)
	)


func _fail(message: String) -> bool:
	last_error = message
	return false
