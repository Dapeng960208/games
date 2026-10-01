extends SceneTree
## PCM design metrics support, never replace, a separate real listening review.
const Audio = preload("res://scripts/combat/combat_audio.gd")
const BASELINE_PATH: String = "res://artifacts/audio/contact_design_before.json"
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CONTACT AUDIO DESIGN FAIL: " + label)

func _measure(stream: AudioStreamWAV) -> Dictionary:
	var result: Dictionary = {"energy":0.0, "onset":0.0, "tail":0.0, "low":0.0, "mid":0.0, "high":0.0, "peak":0.0, "mean":0.0}
	var low: float = 0.0
	var upper: float = 0.0
	var low_alpha: float = 1.0 - exp(-TAU * 260.0 / stream.mix_rate)
	var upper_alpha: float = 1.0 - exp(-TAU * 1600.0 / stream.mix_rate)
	for index: int in stream.data.size() / 2:
		var sample_value: float = float(stream.data.decode_s16(index * 2)) / 32768.0
		var energy: float = sample_value * sample_value / stream.mix_rate
		low += low_alpha * (sample_value - low)
		upper += upper_alpha * (sample_value - upper)
		result.energy += energy
		if index < roundi(0.030 * stream.mix_rate): result.onset += energy
		if index >= roundi(0.100 * stream.mix_rate): result.tail += energy
		result.low += low * low / stream.mix_rate
		result.mid += (upper - low) * (upper - low) / stream.mix_rate
		result.high += (sample_value - upper) * (sample_value - upper) / stream.mix_rate
		result.peak = maxf(result.peak, absf(sample_value))
		result.mean += sample_value / (stream.data.size() / 2)
	return result

func _run() -> void:
	var game: Node = root.get_node("Game")
	if not str(game.profile_path).contains("test_contact_audio_design"):
		push_error("Refusing non-test audio design profile")
		quit(2)
		return
	var measured: Dictionary = {}
	for hero: String in Audio.HEROES:
		for cue: String in ["attack", "impact", "heavy"]:
			for material: String in (Audio.MATERIALS if cue != "attack" else ["stone"]):
				for variant: int in 4:
					var key: String = "%s/%s/%s/%d" % [hero, cue, material, variant]
					measured[key] = _measure(Audio.stream_for(hero, cue, variant, material))
				var m: Dictionary = measured["%s/%s/%s/0" % [hero, cue, material]]
				print("CONTACT DESIGN %s/%s/%s e=%.6f onset=%.6f tail=%.3f low=%.3f mid=%.3f high=%.3f peak=%.3f" % [hero, cue, material, m.energy, m.onset, m.tail / m.energy, m.low / m.energy, m.mid / m.energy, m.high / m.energy, m.peak])
	if "--capture-baseline" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://artifacts/audio")
		var file: FileAccess = FileAccess.open(BASELINE_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify(measured, "\t"))
		file.close()
		print("CONTACT DESIGN baseline captured from current production PCM")
	else:
		_verify(measured)
		print("CONTACT AUDIO DESIGN: %d checks, %d failures (PCM dynamics/band estimates; no listening claim)" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _average(measured: Dictionary, hero: String, cue: String, material: String) -> Dictionary:
	var result: Dictionary = {"energy":0.0, "onset":0.0, "tail":0.0, "low":0.0, "mid":0.0, "high":0.0}
	for variant: int in 4:
		var m: Dictionary = measured["%s/%s/%s/%d" % [hero, cue, material, variant]]
		for key: String in result: result[key] += float(m[key]) / 4.0
	return result

func _verify(measured: Dictionary) -> void:
	check(Audio.MAX_VOICES == 8 and is_equal_approx(Audio.VOICE_GAIN, 0.14) and is_equal_approx(Audio.SAMPLE_PEAK, 0.74), "new timbre uses existing polyphony/gain/PCM ceiling rather than raising overall volume")
	check(Audio.SAMPLE_PEAK * Audio.VOICE_GAIN * Audio.MAX_VOICES + 0.58 * 0.18 < 0.95, "eight correlated SFX peaks plus authored music peak retain master headroom")
	var baseline: Dictionary = {}
	if FileAccess.file_exists(BASELINE_PATH):
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
		if decoded is Dictionary: baseline = decoded
	for material: String in Audio.MATERIALS:
		var hammer: Dictionary = _average(measured, "CH01", "heavy", material)
		var gun: Dictionary = _average(measured, "CH02", "heavy", material)
		var crystal: Dictionary = _average(measured, "CH03", "heavy", material)
		check(hammer.low / hammer.energy > 0.62 and hammer.low / hammer.energy < 0.88, material + " hammer retains body without returning to the former near-all-low-frequency heavy")
		check(hammer.mid / hammer.energy > 0.09, material + " hammer compression retains identifiable low-mid presence")
		check(gun.low / gun.energy < 0.55 and crystal.low / crystal.energy < 0.55, material + " ranged heavy contacts no longer inherit the hammer sub-bass signature")
		check(gun.onset / gun.energy > 0.73 and gun.tail / gun.energy < 0.065, material + " gun contact is front-loaded with a short tail")
		check(crystal.tail / crystal.energy > 0.035 and crystal.tail / crystal.energy > gun.tail / gun.energy * 1.75, material + " crystal shards remain perceptibly timed apart from short perforation in the temporal energy model")
		check(Audio.stream_for("CH03", "heavy", 0, material).get_length() > Audio.stream_for("CH02", "heavy", 0, material).get_length(), material + " crystal granular decay has a longer authored window than gun impact")
		for hero: String in ["CH02", "CH03"]:
			var release: Dictionary = _average(measured, hero, "attack", "stone")
			var contact: Dictionary = _average(measured, hero, "impact", material)
			check(contact.mid + contact.high > (release.mid + release.high) * 1.15, hero + "/" + material + " real contact has independent mid/high detail above its release at unchanged voice gain")
		for hero: String in Audio.HEROES:
			var light: Dictionary = _average(measured, hero, "impact", material)
			var heavy: Dictionary = _average(measured, hero, "heavy", material)
			check(heavy.energy > 6.0 * Audio.PASSIVE_GAIN * Audio.PASSIVE_GAIN * light.energy, hero + "/" + material + " direct heavy exceeds six independent passive-light layers in the energy model")
			for variant: int in 4:
				for cue: String in ["impact", "heavy"]:
					var m: Dictionary = measured["%s/%s/%s/%d" % [hero, cue, material, variant]]
					check(m.peak <= Audio.SAMPLE_PEAK and absf(m.mean) < 0.003, "%s/%s/%s/v%d stays within peak/DC budget" % [hero, cue, material, variant])
			if not baseline.is_empty():
				var before: Dictionary = _average(baseline, hero, "heavy", material)
				print("CONTACT REDESIGN %s/%s low-band %.1f%% -> %.1f%%; mid/high %.1f%% -> %.1f%%" % [hero, material, before.low / before.energy * 100.0, heavy.low / heavy.energy * 100.0, (before.mid + before.high) / before.energy * 100.0, (heavy.mid + heavy.high) / heavy.energy * 100.0])
