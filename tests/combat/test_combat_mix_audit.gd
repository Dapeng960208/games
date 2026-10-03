extends SceneTree
## Read-only production PCM export for default-gain mix measurements.
const Audio = preload("res://scripts/presentation/combat/combat_audio.gd")
const Music = preload("res://scripts/infrastructure/audio/music_director.gd")
const OUT = "res://artifacts/combat_mix_audit"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for hero: String in Audio.HEROES:
		for cue: String in ["impact", "heavy"]:
			for material: String in Audio.MATERIALS:
				for variation: int in Audio.VARIATIONS:
					var stream: AudioStreamWAV = Audio.stream_for(hero, cue, variation, material)
					var result: Error = stream.save_to_wav(OUT + "/%s_%s_%s_%d.wav" % [hero, cue, material, variation])
					if result != OK:
						push_error("PCM export failed")
						quit(1)
						return
	for context: String in Music.CONTEXTS:
		var stream: AudioStreamWAV = Music.stream_for(context)
		if stream.save_to_wav(OUT + "/music_" + context + ".wav") != OK:
			push_error("Music PCM export failed")
			quit(1)
			return
	var data: Dictionary = {"music_gain":Music.MUSIC_GAIN * .55, "sfx_gain":Audio.VOICE_GAIN * .85, "master":1.0, "music_setting":.55, "sfx_setting":.85, "window_ms":80, "voice_count":Audio.MAX_VOICES}
	var file := FileAccess.open(AssetCatalog.resolve(OUT + "/runtime_gains.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("COMBAT MIX AUDIT: exported 72 production impact variants and 4 imported music PCM streams; no subjective listening claim")
	quit(0)
