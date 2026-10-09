extends Node
var muted = false
var voices: Array = []

func _ready():
	for i in 8:
		var player = AudioStreamPlayer.new()
		player.volume_db = -18
		add_child(player)
		voices.append(player)

func play_event(kind: String):
	if muted: return
	var voice = null
	for v in voices:
		if not v.playing: voice = v; break
	if voice == null: return
	var duration = 0.12 if kind == "shot" else (0.7 if kind in ["explosion","nuclear"] else 0.25)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var data = PackedByteArray()
	data.resize(int(duration*22050)*2)
	var frequency = 140.0 if kind == "shot" else (52.0 if kind in ["explosion","nuclear"] else 620.0)
	var sound_rng = RandomNumberGenerator.new()
	sound_rng.seed = 110
	for i in int(duration*22050):
		var t = float(i)/22050.0
		var envelope = pow(1.0-t/duration,2)
		var wave = sin(t*TAU*frequency*(1.0-t/duration*0.65))*0.6
		if kind in ["shot","explosion","nuclear"]: wave += sound_rng.randf_range(-0.4,0.4)
		data.encode_s16(i*2,int(wave*envelope*14000))
	stream.data = data
	voice.stream = stream
	voice.play()
