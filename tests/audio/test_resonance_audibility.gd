extends SceneTree
## Read-only production PCM comparison. No settings, synth or mixer mutations.
const Audio = preload("res://scripts/presentation/combat/combat_audio.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not str(root.get_node("Game").profile_path).contains("test_resonance_audibility"):
		quit(2)
		return
	var output: Array = []
	for spec: Array in [["resonance_1","",Audio.RESONANCE_GAINS[0]],["resonance_2","",Audio.RESONANCE_GAINS[1]],["resonance_full","",Audio.RESONANCE_GAINS[2]],["node_fire","",Audio.DEPLOYMENT_GAINS.node_fire],["attack","CH03",1.0],["impact","CH03",1.0],["heavy","CH03",1.0]]:
		var cue: String = spec[0]
		var gain: float = Audio.VOICE_GAIN*0.85*float(spec[2])
		var metrics: Array = []
		var averages: Dictionary = {"peak":0.0,"rms":0.0,"peak20ms_rms":0.0}
		for variant: int in 4:
			var stream: AudioStreamWAV = Audio.stream_for(spec[1],cue,variant)
			var m: Dictionary = measure(stream)
			metrics.append(m)
			for key: String in averages: averages[key] += float(m[key])/4.0
		var result: Dictionary = {"cue":cue,"event_gain":spec[2],"runtime_gain_at_master1_sfx085":gain,"duration":Audio.stream_for(spec[1],cue).get_length(),"pcm_average":averages,"variants":metrics,"mixed":{}}
		for key: String in averages:
			result.mixed[key] = {"linear":float(averages[key])*gain,"dbfs":linear_to_db(float(averages[key])*gain)}
		output.append(result)
		print("AUDIBILITY ", cue, " gain=", gain, " duration=", result.duration, " PCM=", averages, " MIXED=", result.mixed)
	DirAccess.make_dir_recursive_absolute("res://artifacts/resonance_audio")
	var file: FileAccess = FileAccess.open(AssetCatalog.resolve("res://artifacts/resonance_audio/audibility_comparison.json"),FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(output,"\t"))
		file.close()
	print("AUDIBILITY measured actual production PCM; numeric comparison only, no listening claim")
	quit(0)

func measure(stream: AudioStreamWAV) -> Dictionary:
	var count: int = stream.data.size()/2
	var window: int = roundi(stream.mix_rate*0.02)
	var squares: PackedFloat64Array = []
	squares.resize(count)
	var sum: float = 0.0
	var rolling: float = 0.0
	var max_window: float = 0.0
	var peak: float = 0.0
	for index: int in count:
		var value: float = float(stream.data.decode_s16(index*2))/32768.0
		squares[index] = value*value
		sum += squares[index]
		peak = maxf(peak,absf(value))
		rolling += squares[index]
		if index >= window: rolling -= squares[index-window]
		if index >= window-1: max_window = maxf(max_window,rolling/window)
	return {"peak":peak,"rms":sqrt(sum/count),"peak20ms_rms":sqrt(max_window)}
