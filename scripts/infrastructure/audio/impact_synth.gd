extends RefCounted
## Original procedural Foley: excitation noise, damped material modes and pressure.
## Each variant changes excitation, timing, modal balance and debris, never playback pitch.

const RATE: int = 24000
const PEAK: float = 0.74
const VARIANTS: int = 4
const MATERIALS: Array[String] = ["stone", "metal", "organic"]

static func duration(hero: String, cue: String) -> float:
	if cue.begins_with("prepare_"):
		return 0.16 if cue == "prepare_ultimate" else 0.12
	match cue:
		"resonance_1": return 0.11
		"resonance_2": return 0.14
		"resonance_full": return 0.19
		"trap_trigger": return 0.17
		"node_fire": return 0.12
		"field_pulse": return 0.19
		"grenade_burst": return 0.34
		"defeat": return 0.30
		"hurt": return 0.22
		"pickup": return 0.27
		"ultimate": return {"CH01":0.36, "CH02":0.19, "CH03":0.42}.get(hero, 0.36)
		"secondary": return {"CH01":0.28, "CH02":0.23, "CH03":0.26}.get(hero, 0.28)
		"f": return {"CH01":0.26, "CH02":0.18, "CH03":0.32}.get(hero, 0.26)
		"q": return {"CH01":0.22, "CH02":0.16, "CH03":0.25}.get(hero, 0.22)
		"heavy": return {"CH01":0.34, "CH02":0.26, "CH03":0.38}.get(hero, 0.34)
		"impact": return {"CH01":0.24, "CH02":0.16, "CH03":0.29}.get(hero, 0.24)
		_: return 0.16 if hero == "CH02" else 0.26

static func synthesize(hero: String, cue: String, variant: int, material: String) -> AudioStreamWAV:
	var length: float = duration(hero, cue)
	var samples := PackedFloat32Array()
	samples.resize(ceili(length * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = ("foley-v2:" + hero + ":" + cue + ":" + str(variant) + ":" + material).hash()
	if cue.begins_with("prepare_"):
		_prepare(samples, rng, hero, cue.trim_prefix("prepare_"))
	elif cue in ["resonance_1", "resonance_2", "resonance_full"]:
		_resonance(samples, rng, cue)
	elif cue in ["trap_trigger", "node_fire", "field_pulse", "grenade_burst"]:
		_deployment(samples, rng, cue)
	elif cue == "defeat":
		_defeat(samples, rng, material)
	elif cue == "hurt":
		_pressure(samples, 0.0, 0.20, 0.66, 93.0, 42.0, 25.0)
		_noise(samples, rng, 0.0, 0.16, 0.48, 450.0, 2200.0, 35.0)
	elif cue == "pickup":
		for note: int in 3:
			_mode(samples, float(note) * 0.057 + rng.randf_range(0.0, 0.003), 0.15, [660.0, 880.0, 1100.0][note], rng.randf_range(0.26, 0.31), rng.randf_range(28.0, 34.0))
	elif cue in ["impact", "heavy"]:
		_hit(samples, rng, hero, cue == "heavy", material)
	else:
		match hero:
			"CH01": _axe_release(samples, rng, cue)
			"CH02": _gun_release(samples, rng, cue)
			"CH03": _arcane_release(samples, rng, cue)
	return _pcm(samples)

static func _resonance(out: PackedFloat32Array, rng: RandomNumberGenerator, cue: String) -> void:
	# Ceramic capacitor teeth seat into a socket. No bass pressure, pitched
	# reward melody or extended particle tail borrowed from a bolt/impact.
	var touch: float = rng.randf_range(0.92, 1.08)
	_noise(out, rng, 0.0, 0.017, 0.43, 1000.0, 5000.0, 135.0)
	_modes(out, 0.001, 0.038, [733.0, 1249.0], [0.15, 0.065], 89.0, touch)
	match cue:
		"resonance_1":
			# One dry tooth seats; a small quiet contact gives level one its shape.
			_noise(out, rng, rng.randf_range(0.013, 0.017), 0.022, 0.19, 800.0, 2500.0, 105.0)
		"resonance_2":
			# A second contact closes more firmly, adding an upper ceramic edge.
			var at: float = rng.randf_range(0.018, 0.022)
			_noise(out, rng, at, 0.028, 0.43, 1600.0, 5900.0, 87.0)
			_modes(out, at, 0.045, [1627.0, 2731.0], [0.17, 0.072], 72.0, touch)
		"resonance_full":
			# The two-part latch locks shut: wider dry closure, then a compact
			# inharmonic confirmation. It is a mechanism, not another fired bolt.
			_noise(out, rng, 0.006, 0.024, 0.48, 1700.0, 6200.0, 108.0)
			var at: float = rng.randf_range(0.037, 0.043)
			_noise(out, rng, at, 0.036, 0.68, 600.0, 3400.0, 72.0)
			_modes(out, at, 0.064, [941.0, 2053.0, 3319.0], [0.23, 0.105, 0.05], 59.0, touch)

static func _deployment(out: PackedFloat32Array, rng: RandomNumberGenerator, cue: String) -> void:
	match cue:
		"grenade_burst":
			# Physical detonation at the live fuse event: pressure, hot crack,
			# then irregular metallic fragments. The throw contains none of it.
			_noise(out, rng, 0.0, 0.055, 1.22, 130.0, 5900.0, 57.0)
			_pressure(out, 0.002, 0.23, 0.94, rng.randf_range(179.0, 197.0), 69.0, 18.0)
			_noise(out, rng, 0.014, 0.22, 0.40, 210.0, 2700.0, 16.0)
			for fragment: int in 6:
				var at: float = 0.023 + float(fragment) * 0.033 + rng.randf_range(-0.006, 0.006)
				_noise(out, rng, at, 0.031, 0.23 * (1.0 - float(fragment) * 0.10), 1700.0, 5800.0, 97.0)
				_mode(out, at, 0.05, rng.randf_range(1490.0, 2770.0), 0.018, 76.0)
		"trap_trigger":
			# A cold-line latch snaps open, followed by a short pressure vent.
			# No gun report or sub-bass explosion is hidden in this mechanism.
			_noise(out, rng, 0.0, 0.025, 0.74, 490.0, 4900.0, 105.0)
			_modes(out, 0.001, 0.055, [463.0, 1123.0, 2297.0], [0.15, 0.07, 0.025], 73.0, rng.randf_range(0.9, 1.1))
			_noise(out, rng, 0.009, 0.115, 0.44, 1500.0, 5400.0, 30.0)
		"node_fire":
			# One compact crystalline discharge per successfully emitted bolt.
			_noise(out, rng, 0.0, 0.048, 0.65, 1400.0, 6600.0, 71.0)
			_modes(out, 0.001, 0.055, [1621.0, 2539.0], [0.095, 0.045], 58.0, rng.randf_range(0.9, 1.1))
			_pressure(out, 0.002, 0.045, 0.16, 245.0, 145.0, 63.0)
			_sparks(out, rng, 0.010, 0.038, 3, 0.105)
		"field_pulse":
			# A light expanding energy breath, underneath the player's spells.
			_noise(out, rng, 0.0, 0.15, 0.43, 450.0, 3200.0, 23.0, 0.005)
			_modes(out, 0.002, 0.11, [347.0, 611.0, 1031.0], [0.065, 0.035, 0.018], 35.0, rng.randf_range(0.88, 1.12))

static func _defeat(out: PackedFloat32Array, rng: RandomNumberGenerator, material: String) -> void:
	# A quiet material collapse sits behind the killing impact. No sub-bass slam,
	# pitched reward motif or normalized loudness competes with the player's hit.
	match material:
		"metal":
			_noise(out, rng, 0.0, 0.070, 0.41, 680.0, 4200.0, 42.0)
			for part: int in 5:
				var start: float = 0.019 + float(part) * 0.037 + rng.randf_range(-0.008, 0.008)
				var gain: float = rng.randf_range(0.16, 0.24) * (1.0 - float(part) * 0.11)
				_noise(out, rng, start, 0.042, gain, 500.0, 5400.0, 72.0)
				# Short unequal metal modes sound like loose parts, never a ringing bell.
				_mode(out, start, 0.057, rng.randf_range(470.0, 830.0), gain * 0.30, 66.0)
				_mode(out, start + 0.003, 0.046, rng.randf_range(1390.0, 2410.0), gain * 0.13, 82.0)
		"organic":
			_noise(out, rng, 0.0, 0.14, 0.53, 155.0, 1400.0, 29.0)
			_pressure(out, 0.004, 0.080, 0.115, rng.randf_range(180.0, 210.0), 115.0, 46.0)
			for fragment: int in 5:
				var start: float = 0.022 + float(fragment) * 0.033 + rng.randf_range(-0.007, 0.007)
				_noise(out, rng, start, 0.041, rng.randf_range(0.12, 0.22), 280.0, rng.randf_range(1500.0, 2300.0), 63.0)
		_:
			_noise(out, rng, 0.0, 0.075, 0.44, 440.0, 3800.0, 46.0)
			for grain: int in 8:
				var start: float = 0.021 + float(grain) * 0.027 + rng.randf_range(-0.007, 0.007)
				_noise(out, rng, start, rng.randf_range(0.023, 0.042), rng.randf_range(0.10, 0.23) * (1.0 - float(grain) * 0.055), 740.0, rng.randf_range(3100.0, 5700.0), 76.0)

static func _hit(out: PackedFloat32Array, rng: RandomNumberGenerator, hero: String, heavy: bool, material: String) -> void:
	# Contact exists only in this branch. Release cues never manufacture target Foley.
	# Small ranged contacts need a clear crack against their release, without
	# recovering loudness by putting the removed sub-bass back into the mix.
	var mass: float = 1.0 if heavy else (0.55 if hero == "CH01" else 0.72)
	var spread: float = rng.randf_range(0.92, 1.08)
	match hero:
		"CH01":
			# Axe contact has a low-mid chest and a brief steel cutting edge.
			# Face contact, compressed body and fractured grit remain audible.
			_noise(out, rng, 0.0, 0.031, 1.18 * mass, 550.0, 5800.0, 105.0)
			_modes(out, 0.002, 0.057, [659.0, 1177.0, 2053.0], [0.09, 0.035, 0.014], 79.0, mass * spread)
			_pressure(out, 0.002, 0.23 if heavy else 0.16, (1.20 if heavy else 1.00) * mass, 158.0 * spread, 83.0, 19.0 if heavy else 31.0)
			_modes(out, 0.002, 0.11, [229.0, 419.0, 811.0, 1583.0], [0.38 if heavy else 0.28, 0.18, 0.06, 0.025], 37.0, spread * mass)
			_noise(out, rng, 0.013, 0.12, 0.37 * mass, 220.0, 1850.0, 29.0)
			if heavy:
				_pressure(out, 0.013, 0.17, 0.60, 136.0, 75.0, 21.0)
				_noise(out, rng, 0.020, 0.14, 0.37, 180.0, 1200.0, 25.0)
		"CH02":
			# A dense immediate perforation crack has its own mid/high-frequency
			# identity against the gun report. No hammer-like low rolling tail.
			_noise(out, rng, 0.0, 0.024, 2.30 * mass, 900.0, 6900.0, 110.0)
			_noise(out, rng, 0.001, 0.019, 0.10 * mass, 2400.0, 7100.0, 136.0)
			_noise(out, rng, rng.randf_range(0.002, 0.004), 0.033, 1.24 * mass, 550.0, 3900.0, 85.0)
			_modes(out, 0.001, 0.048, [1423.0, 2339.0, 3761.0], [0.17, 0.095, 0.042], 80.0, spread * mass)
			_pressure(out, 0.002, 0.075 if heavy else 0.055, 0.57 * mass, 370.0, 180.0, 43.0 if heavy else 63.0)
			if heavy:
				_noise(out, rng, 0.006, 0.045, 0.40, 800.0, 4700.0, 62.0)
				_pressure(out, 0.006, 0.075, 0.24, 290.0, 125.0, 49.0)
		"CH03":
			# Crystal deconstruction: an irregular brittle crack, short body,
			# then distinct granular shards rather than a pitched reward bell.
			_noise(out, rng, 0.0, 0.066, 1.32 * mass, 980.0, 6600.0, 52.0)
			_modes(out, 0.001, 0.13, [1183.0, 1877.0, 2833.0, 4219.0], [0.34, 0.21, 0.11, 0.055], 36.0, spread * mass)
			_pressure(out, 0.003, 0.10 if heavy else 0.075, 0.39 * mass, 230.0, 120.0, 37.0 if heavy else 49.0)
			_sparks(out, rng, 0.026, 0.25 if heavy else 0.16, 14 if heavy else 7, mass * (0.55 if heavy else 0.40))
			# A faint harmonic afterglow joins the real brittle contact rather
			# than inserting a second impact or a low-frequency explosion.
			_modes(out, 0.020, 0.15, [587.33, 880.0, 1174.66], [0.028, 0.014, 0.008], 27.0, mass)
			if heavy:
				_noise(out, rng, 0.007, 0.12, 0.69, 1300.0, 6500.0, 39.0)
				_mode(out, 0.011, 0.09, 2693.0 * spread, 0.14, 43.0)
	_material(out, rng, material, heavy, mass)

static func _material(out: PackedFloat32Array, rng: RandomNumberGenerator, material: String, heavy: bool, gain: float) -> void:
	match material:
		"metal":
			_modes(out, 0.004, 0.24 if heavy else 0.16, [547.0, 913.0, 1589.0, 2683.0], [0.22, 0.14, 0.085, 0.04], 19.0 if heavy else 30.0, gain)
			_noise(out, rng, 0.008, 0.078, gain * 0.60, 1400.0, 5700.0, 54.0)
		"organic":
			_noise(out, rng, 0.002, 0.115, gain * 1.24, 110.0, 1450.0, 34.0)
			_pressure(out, 0.004, 0.13, gain * 0.45, 175.0, 72.0, 32.0)
			for fragment: int in 4:
				var start: float = rng.randf_range(0.012, 0.068)
				_noise(out, rng, start, 0.019, gain * rng.randf_range(0.12, 0.26), 500.0, 2500.0, 100.0)
		_:
			_noise(out, rng, 0.003, 0.11, gain * 0.77, 230.0, 3100.0, 37.0)
			# Individual dry grains have irregular timing and changing noise bandwidth.
			for fragment: int in (8 if heavy else 5):
				var start: float = 0.026 + float(fragment) * 0.019 + rng.randf_range(-0.006, 0.006)
				_noise(out, rng, start, rng.randf_range(0.020, 0.039), gain * rng.randf_range(0.13, 0.32), 720.0, rng.randf_range(2700.0, 4900.0), 65.0)
				_mode(out, start, 0.038, rng.randf_range(620.0, 1800.0), gain * 0.035, 85.0)

static func _prepare(out: PackedFloat32Array, rng: RandomNumberGenerator, hero: String, slot: String) -> void:
	# Short commitment texture only. No report/impact hidden later in this WAV;
	# actual releases remain owned by the cancellable ability timeline.
	var strength: float = 0.42 if slot == "ultimate" else 0.29
	var color: float = {"q":1.12, "secondary":0.83, "f":1.37, "ultimate":0.70}.get(slot, 1.0)
	match hero:
		"CH01":
			_noise(out, rng, 0.0, 0.10, strength, 180.0 * color, 1700.0, 26.0, 0.009)
			_modes(out, 0.003, 0.06, [391.0 * color, 1027.0 * color], [0.07, 0.025], 49.0, rng.randf_range(0.9, 1.1))
		"CH02":
			_noise(out, rng, 0.0, 0.035, strength, 720.0 * color, 4000.0, 77.0)
			_noise(out, rng, 0.028, 0.046, strength * 0.45, 340.0, 2100.0 * color, 48.0)
			_mode(out, 0.002, 0.033, 961.0 * color, 0.035, 80.0)
		"CH03":
			_noise(out, rng, 0.0, 0.11, strength, 1200.0 * color, 5700.0, 16.0, 0.020)
			_modes(out, 0.0, 0.105, [587.33 * color, 880.0 * color, 1174.66 * color], [0.055, 0.028, 0.013], 17.0, rng.randf_range(0.92, 1.08))

static func _axe_release(out: PackedFloat32Array, rng: RandomNumberGenerator, cue: String) -> void:
	if cue == "attack":
		# Broad wind builds then passes; no impact thud on a miss.
		_noise(out, rng, 0.0, 0.23, 0.66, 90.0, 1450.0, 8.0, 0.045)
		_noise(out, rng, 0.036, 0.15, 0.31, 800.0, 3700.0, 15.0, 0.021)
		_mode(out, 0.015, 0.045, 291.0, 0.16, 56.0)
		_modes(out, 0.009, 0.063, [659.0, 1439.0], [0.064, 0.025], 54.0, rng.randf_range(0.9, 1.1))
		_noise(out, rng, 0.013, 0.038, 0.28, 350.0, 2700.0, 88.0)
		return
	if cue == "secondary":
		# A loaded grip releases, then the broad axe blade sweeps the air.
		# The wind crests after the small mechanical release instead of bursting
		# on frame zero. Neither armour/flesh contact nor a heavy thud lives here.
		_noise(out, rng, 0.0, 0.022, 0.51, 1100.0, 5800.0, 102.0)
		_modes(out, 0.001, 0.034, [1171.0, 2473.0], [0.075, 0.028], 104.0, rng.randf_range(0.90,1.10))
		var wind_start: float = rng.randf_range(0.010,0.016)
		var wind_rise: float = rng.randf_range(0.054,0.066)
		_noise(out, rng, wind_start, 0.224, 1.58, rng.randf_range(150.0,210.0), rng.randf_range(2450.0,2850.0), 7.0, wind_rise)
		_noise(out, rng, wind_start+0.027, 0.174, 0.78, 850.0, rng.randf_range(4500.0,5200.0), 10.0, 0.044)
		_noise(out, rng, wind_start+0.076, 0.128, 0.36, 1850.0, 6200.0, 13.0, 0.026)
		return
	if cue == "f":
		# Planting the weapon and setting armour: a short steel latch and breath.
		_noise(out, rng, 0.0, 0.024, 0.86, 550.0, 4300.0, 96.0)
		_modes(out, 0.001, 0.17, [293.0, 653.0, 1457.0], [0.29, 0.11, 0.045], 28.0, rng.randf_range(0.92, 1.08))
		_noise(out, rng, 0.007, 0.20, 0.55, 190.0, 1900.0, 19.0)
		return
	# One broad cutting release per real swing; body contact remains _hit.
	var force: float = 1.32 if cue == "ultimate" else 1.04
	var length: float = 0.30 if cue == "ultimate" else 0.19
	_noise(out, rng, 0.0, length, force, 90.0, 1850.0, 16.0, 0.001)
	_noise(out, rng, 0.002, 0.11, force * 0.92, 740.0, 5200.0, 40.0)
	_modes(out, 0.003, 0.09, [291.0, 653.0, 1477.0], [0.23, 0.082, 0.027], 46.0, force)
	if cue == "ultimate":
		_noise(out, rng, 0.008, 0.24, 0.51, 360.0, 3200.0, 19.0)
	else:
		_noise(out, rng, 0.006, 0.14, 0.46, 940.0, 3600.0, 30.0)

static func _gun_release(out: PackedFloat32Array, rng: RandomNumberGenerator, cue: String) -> void:
	if cue == "f":
		# One pulled pin and an arm's throwing rush. Explosive sound is owned
		# by the grenade's live fuse, including misses and post-throw dashes.
		_noise(out, rng, 0.0, 0.023, 0.74, 950.0, 5200.0, 110.0)
		_modes(out, 0.001, 0.045, [823.0, 1913.0, 3079.0], [0.15, 0.055, 0.026], 83.0, rng.randf_range(0.92, 1.08))
		_noise(out, rng, 0.009, 0.11, 0.91, 230.0, 3100.0, 22.0, 0.011)
		return
	var cannon: bool = cue == "secondary"
	var force: float = {"attack":0.85, "q":0.77, "secondary":1.30, "ultimate":1.05}.get(cue, 0.85)
	# One immediate bolt/report, then a quiet extractor. Cadence belongs to the
	# actual projectile events, so branches/cancellation cannot invent shots.
	_noise(out, rng, 0.0, 0.015, 0.32, 1200.0, 5100.0, 180.0)
	_modes(out, 0.0, 0.024, [773.0, 1703.0], [0.10, 0.035], 105.0, rng.randf_range(0.86, 1.1))
	_noise(out, rng, 0.002, 0.085 if cannon else 0.052, force * 1.40, 110.0, 5300.0, 50.0 if cannon else 78.0)
	_noise(out, rng, 0.001, 0.015, force * 0.32, 2200.0, 7300.0, 142.0)
	_pressure(out, 0.003, 0.17 if cannon else 0.09, force * 0.57, 155.0 if cannon else 245.0, 52.0 if cannon else 93.0, 29.0 if cannon else 58.0)
	_noise(out, rng, rng.randf_range(0.048, 0.059), 0.035, 0.24, 650.0, 3800.0, 96.0)
	_mode(out, 0.055, 0.034, rng.randf_range(820.0, 1110.0), 0.09, 85.0)

static func _arcane_release(out: PackedFloat32Array, rng: RandomNumberGenerator, cue: String) -> void:
	var power: float = 0.61 if cue == "attack" else (1.0 if cue == "ultimate" else 0.80)
	if cue == "secondary":
		# Runic crystal placement: gentle contact and an opening harmonic aura.
		_noise(out, rng, 0.0, 0.040, 0.57, 650.0, 4700.0, 75.0)
		_modes(out, 0.001, 0.17, [587.33, 880.0, 1174.66], [0.16, 0.078, 0.035], 23.0, rng.randf_range(0.91, 1.09))
		_sparks(out, rng, 0.014, 0.14, 9, 0.19)
		return
	# Immediate release transient; charge sound was already played on commitment.
	_noise(out, rng, 0.0, 0.080, power * 1.15, 740.0, 6400.0, 52.0)
	_modes(out, 0.003, 0.17, [587.33, 880.0, 1760.0], [0.093, 0.038, 0.017], 24.0, power)
	_pressure(out, 0.002, 0.19, power * 0.57, 203.0, 82.0, 28.0)
	_sparks(out, rng, 0.015, 0.12, 5, power * 0.20)
	if cue == "q":
		_noise(out, rng, 0.006, 0.18, 0.56, 850.0, 5600.0, 24.0)
	elif cue == "f":
		_noise(out, rng, 0.003, 0.25, 0.75, 110.0, 3100.0, 17.0)
		_modes(out, 0.004, 0.17, [411.0, 709.0, 1297.0], [0.17, 0.08, 0.035], 28.0, 1.0)
	elif cue == "ultimate":
		_noise(out, rng, 0.006, 0.35, 0.76, 370.0, 5400.0, 12.0)
		_pressure(out, 0.005, 0.23, 0.36, 223.0, 123.0, 24.0)
		_modes(out, 0.008, 0.33, [293.66, 440.0, 587.33], [0.20, 0.10, 0.05], 15.0, 1.0)
		_sparks(out, rng, 0.025, 0.27, 14, 0.25)

static func _sparks(out: PackedFloat32Array, rng: RandomNumberGenerator, start: float, length: float, count: int, gain: float) -> void:
	for spark: int in count:
		var at: float = start + rng.randf_range(0.0, length)
		_noise(out, rng, at, 0.014, gain * rng.randf_range(0.5, 1.0), 1700.0, 7000.0, 160.0)
		_mode(out, at, 0.035, rng.randf_range(1750.0, 4600.0), gain * 0.16, 105.0)

static func _noise(out: PackedFloat32Array, rng: RandomNumberGenerator, start: float, length: float, gain: float, low_hz: float, high_hz: float, decay: float, attack: float = 0.0007) -> void:
	var first: int = maxi(0, roundi(start * RATE))
	var last: int = mini(out.size(), roundi((start + length) * RATE))
	var low: float = 0.0
	var high: float = 0.0
	var a: float = 1.0 - exp(-TAU * high_hz / RATE)
	var b: float = 1.0 - exp(-TAU * low_hz / RATE)
	for i: int in range(first, last):
		var t: float = float(i - first) / RATE
		low += a * (rng.randf_range(-1.0, 1.0) - low)
		high += b * (low - high)
		out[i] += (low - high) * gain * exp(-t * decay) * _envelope(t, length, attack)

static func _mode(out: PackedFloat32Array, start: float, length: float, hz: float, gain: float, decay: float, attack: float = 0.0008) -> void:
	var first: int = maxi(0, roundi(start * RATE))
	var last: int = mini(out.size(), roundi((start + length) * RATE))
	for i: int in range(first, last):
		var t: float = float(i - first) / RATE
		out[i] += sin(TAU * hz * t) * gain * exp(-t * decay) * _envelope(t, length, attack)

static func _modes(out: PackedFloat32Array, start: float, length: float, frequencies: Array, gains: Array, decay: float, scale: float) -> void:
	for mode: int in frequencies.size():
		_mode(out, start, length, float(frequencies[mode]), float(gains[mode]) * scale, decay * (1.0 + mode * 0.18))

static func _pressure(out: PackedFloat32Array, start: float, length: float, gain: float, hz: float, end_hz: float, decay: float) -> void:
	var first: int = maxi(0, roundi(start * RATE))
	var last: int = mini(out.size(), roundi((start + length) * RATE))
	var phase: float = 0.0
	for i: int in range(first, last):
		var t: float = float(i - first) / RATE
		# The pressure drops rapidly then settles; a short physical body, no laser sweep.
		phase += TAU * (end_hz + (hz - end_hz) * exp(-t * 48.0)) / RATE
		out[i] += (sin(phase) + sin(phase * 2.03) * 0.16) * gain * exp(-t * decay) * _envelope(t, length, 0.002)

static func _envelope(t: float, length: float, attack: float) -> float:
	return minf(1.0, t / attack) * minf(1.0, maxf(0.0, length - t) / 0.008)

static func _pcm(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	var previous: float = 0.0
	var dc: float = 0.0
	var smoothed: float = 0.0
	var output_smooth: float = 0.0
	for i: int in samples.size():
		# Fixed transfer preserves light/heavy and release/contact energy differences.
		# DC blocking and a gentle high rolloff retain mass without hash or clicks.
		var value: float = samples[i] - previous + 0.996 * dc
		previous = samples[i]
		dc = value
		smoothed += 0.60 * (value - smoothed)
		value = tanh(smoothed * 1.35) * PEAK
		output_smooth += 0.62 * (value - output_smooth)
		value = output_smooth
		value *= minf(1.0, float(i) / 18.0) * minf(1.0, float(samples.size() - 1 - i) / 240.0)
		bytes.encode_s16(i * 2, roundi(value * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = bytes
	return stream
