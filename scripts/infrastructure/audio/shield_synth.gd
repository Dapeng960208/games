extends RefCounted
## Original shield Foley: a tensioned membrane/armour face and a single fracture.
## Shared excitation/PCM primitives retain the established peak and DC budget;
## these are distinct generated signals, not reused body-impact recordings.
const Foley = preload("res://scripts/infrastructure/audio/impact_synth.gd")
const VARIANTS: int = 4
const CUES: Array[String] = ["shield_hit", "shield_break"]

static func duration(hero: String, broken: bool) -> float:
	return {"CH01":0.24,"CH02":0.22,"CH03":0.26}.get(hero,0.24) if broken else {"CH01":0.16,"CH02":0.14,"CH03":0.18}.get(hero,0.16)

static func synthesize(hero: String, broken: bool, variant: int) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	out.resize(ceili(duration(hero,broken)*Foley.RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = ("shield-foley-v1:"+hero+":"+str(broken)+":"+str(variant)).hash()
	var touch: float = rng.randf_range(0.94,1.06)
	var modes: Array = {"CH01":[457.0,1031.0,2267.0],"CH02":[947.0,1987.0,3613.0],"CH03":[683.0,1549.0,2927.0]}.get(hero,[457.0,1031.0,2267.0])
	if not broken:
		# A firmly seated face with a small high edge; no flesh/gravel fragments.
		Foley._noise(out,rng,0.0,0.028,1.03,520.0,5400.0,88.0)
		Foley._modes(out,0.002,0.110,modes,[0.39,0.21,0.095],32.0,touch)
		if hero == "CH01":
			# Hammer load spreads across a broad armour plate.
			Foley._noise(out,rng,0.009,0.063,0.49,290.0,2000.0,41.0)
		elif hero == "CH02":
			# A ricochet-like scoring edge follows the projectile's point contact.
			Foley._noise(out,rng,0.006,0.038,0.59,2200.0,6900.0,81.0)
		else:
			# A membrane briefly flexes into unequal crystal modes, not a hum.
			Foley._modes(out,0.009,0.090,[1193.0,2081.0],[0.14,0.075],38.0,touch)
	else:
		# The fracture has one stronger immediate crack, then thin detached flakes.
		# It replaces the body contact even when that same packet also damages HP.
		Foley._noise(out,rng,0.0,0.048,1.82,650.0,6600.0,66.0)
		Foley._modes(out,0.002,0.135,modes,[0.56,0.29,0.135],25.0,touch)
		Foley._noise(out,rng,0.010,0.079,0.73,340.0,2900.0,34.0)
		for flake: int in 5:
			var at: float = 0.024+float(flake)*0.023+rng.randf_range(-0.004,0.004)
			Foley._noise(out,rng,at,0.017,0.23*(1.0-float(flake)*0.12),1800.0,6500.0,135.0)
			Foley._mode(out,at,0.031,rng.randf_range(1850.0,3750.0),0.045,93.0)
	return Foley._pcm(out)
