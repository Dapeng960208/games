extends RefCounted
## Original one-shot role motifs. No recordings, external samples or looping music.
## Motifs share D Dorian with the score, but each role owns its instrumentation.

const RATE: int = 24000
const PEAK: float = 0.56
const HEROES: Array[String] = ["CH01", "CH02", "CH03"]
const SLOTS: Array[String] = ["q", "secondary", "f", "ultimate"]
const LENGTHS: Dictionary = {"q":0.68, "secondary":0.78, "f":0.72, "ultimate":1.18}
const NOTES: Dictionary = {
	"q":[62, 69, 74],
	"secondary":[62, 65, 69],
	"f":[57, 62, 64],
	"ultimate":[50, 57, 62, 69, 74],
}

static var _streams: Dictionary = {}

static func prewarm() -> void:
	for hero: String in HEROES:
		for slot: String in SLOTS:
			stream_for(hero, slot)

static func stream_for(hero: String, slot: String) -> AudioStreamWAV:
	if hero not in HEROES or slot not in SLOTS:
		return null
	var key: String = hero + ":" + slot
	if not _streams.has(key):
		_streams[key] = _synthesize(hero, slot)
	return _streams[key]

static func _synthesize(hero: String, slot: String) -> AudioStreamWAV:
	var length: float = float(LENGTHS[slot])
	var out := PackedFloat32Array()
	out.resize(roundi(length * RATE))
	var pitches: Array = NOTES[slot]
	var rng := RandomNumberGenerator.new()
	rng.seed = ("role-motif-v1:" + hero + ":" + slot).hash()
	# Start just behind the physical release, leaving its first transient clear.
	match hero:
		"CH01":
			# Brass fifths above two compact war-drum gestures: weight and resolve.
			_drum(out, 0.014, 0.22, 0.44, 128.0, rng)
			_drum(out, 0.19 if slot != "ultimate" else 0.31, 0.17, 0.24, 161.0, rng)
			for index: int in pitches.size():
				var at: float = 0.035 + float(index) * (0.116 if slot != "ultimate" else 0.151)
				_note(out, "brass", int(pitches[index]) - 12, at, 0.30, 0.24 if index == 0 else 0.19)
				if index == pitches.size() - 1:
					_note(out, "brass", int(pitches[index]) - 5, at, 0.34, 0.095)
		"CH02":
			# A dry muted-string signal and a brushed snare. These contain no
			# gun reports: all shots still come from individual real projectiles.
			for index: int in pitches.size():
				var at: float = 0.024 + float(index) * (0.101 if slot != "ultimate" else 0.135)
				_note(out, "pluck", int(pitches[index]) + 12, at, 0.19, 0.33 if index % 2 == 0 else 0.24)
				_brush(out, rng, at + 0.033, 0.057, 0.065 if index == 0 else 0.035)
			_note(out, "pluck", int(pitches[0]), 0.025, 0.28, 0.12)
		"CH03":
			# Glass harmonics blossom into a short open chord and diffuse echoes.
			for index: int in pitches.size():
				var at: float = 0.024 + float(index) * (0.122 if slot != "ultimate" else 0.165)
				var pitch: int = int(pitches[index]) + 12
				_note(out, "glass", pitch, at, 0.37, 0.27)
				_note(out, "glass", pitch, at + 0.125, 0.30, 0.063)
				if index == 0:
					_note(out, "air", pitch - 12, at, length - 0.09, 0.12)
	return _pcm(out)

static func _note(out: PackedFloat32Array, instrument: String, midi: int, start: float, length: float, gain: float) -> void:
	var hz: float = 440.0 * pow(2.0, float(midi - 69) / 12.0)
	var first: int = roundi(start * RATE)
	var last: int = mini(out.size(), roundi((start + length) * RATE))
	for index: int in range(first, last):
		var t: float = float(index - first) / RATE
		var attack: float = 0.018 if instrument == "brass" else (0.036 if instrument == "air" else 0.004)
		var envelope: float = minf(1.0, t / attack) * minf(1.0, maxf(0.0, length - t) / 0.065)
		var value: float = sin(TAU * hz * t)
		match instrument:
			"brass":
				value += 0.29 * sin(TAU * hz * 2.0 * t) + 0.12 * sin(TAU * hz * 3.0 * t) + 0.04 * sin(TAU * hz * 4.0 * t)
				envelope *= exp(-t * 6.0)
			"pluck":
				value += 0.19 * sin(TAU * hz * 2.0 * t) * exp(-t * 13.0) + 0.09 * sin(TAU * hz * 3.0 * t) * exp(-t * 22.0)
				envelope *= exp(-t * 12.0)
			"glass":
				value = value * 0.74 + 0.22 * sin(TAU * hz * 2.006 * t) + 0.09 * sin(TAU * hz * 3.994 * t)
				envelope *= exp(-t * 5.8)
			"air":
				value = value * 0.5 + 0.25 * sin(TAU * hz * 1.006 * t) + 0.13 * sin(TAU * hz * 2.0 * t)
				envelope *= exp(-t * 4.0)
		out[index] += value * envelope * gain

static func _drum(out: PackedFloat32Array, start: float, length: float, gain: float, hz: float, rng: RandomNumberGenerator) -> void:
	var first: int = roundi(start * RATE)
	var last: int = mini(out.size(), roundi((start + length) * RATE))
	var noise: float = 0.0
	for index: int in range(first, last):
		var t: float = float(index - first) / RATE
		var phase: float = TAU * (hz * 0.65 * t + hz * 0.35 * (1.0 - exp(-t * 35.0)) / 35.0)
		noise += 0.23 * (rng.randf_range(-1.0, 1.0) - noise)
		var envelope: float = minf(1.0, t / 0.003) * minf(1.0, maxf(0.0, length - t) / 0.026)
		out[index] += (sin(phase) * exp(-t * 18.0) + noise * 0.21 * exp(-t * 60.0)) * gain * envelope

static func _brush(out: PackedFloat32Array, rng: RandomNumberGenerator, start: float, length: float, gain: float) -> void:
	var first: int = roundi(start * RATE)
	var last: int = mini(out.size(), roundi((start + length) * RATE))
	var smooth: float = 0.0
	for index: int in range(first, last):
		var t: float = float(index - first) / RATE
		smooth += 0.30 * (rng.randf_range(-1.0, 1.0) - smooth)
		var envelope: float = minf(1.0, t / 0.003) * minf(1.0, maxf(0.0, length - t) / 0.012)
		out[index] += smooth * gain * exp(-t * 35.0) * envelope

static func _pcm(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	var previous: float = 0.0
	var dc: float = 0.0
	var smooth: float = 0.0
	for index: int in samples.size():
		var value: float = samples[index] - previous + 0.998 * dc
		previous = samples[index]
		dc = value
		smooth += 0.72 * (value - smooth)
		value = tanh(smooth * 1.6) * PEAK
		value *= minf(1.0, float(index) / 32.0) * minf(1.0, float(samples.size() - 1 - index) / 480.0)
		bytes.encode_s16(index * 2, roundi(value * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = bytes
	return stream
