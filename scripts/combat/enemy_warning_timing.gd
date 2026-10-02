extends RefCounted
## Shared warning pacing only. Damage, stats, movement, recovery, cooldowns and
## authored geometry are untouched. Call from baseline values, never rescale a
## previously scaled result. Archived V1 profiles retain historical timings.
const TELL_FACTORS: Array[float] = [0.80,0.75,0.70,0.65,0.60]
const LOCK_FACTORS: Array[float] = [0.75,0.70,0.65,0.60,0.55]
const ORDINARY_SHORT_FLOORS: Array[float] = [0.42,0.40,0.38,0.36,0.34]
const ORDINARY_AREA_FLOORS: Array[float] = [0.60,0.57,0.54,0.51,0.48]
const ORDINARY_BOMBER_FLOORS: Array[float] = [0.90,0.85,0.80,0.75,0.70]

static func ordinary(base_tell: float, base_lock: float, difficulty: int, command: Dictionary = {}, ruleset: int = 1) -> Dictionary:
 var d: int = clampi(difficulty,0,4)
 var area: bool = is_area(command)
 var bomber: bool = bool(command.get("bomber",false))
 var family: String = "bomber" if bomber else "area" if area else "short"
 var floor: float = ORDINARY_BOMBER_FLOORS[d] if bomber else ORDINARY_AREA_FLOORS[d] if area else ORDINARY_SHORT_FLOORS[d]
 if ruleset != 2: floor = 0.8 if bool(command.get("warning_area",area)) else 0.55
 return _resolve(base_tell,base_lock,d,floor,0.22 if ruleset==2 else 0.4,family,ruleset)

static func boss(base_tell: float, base_lock: float, difficulty: int, command: Dictionary = {}, ruleset: int = 1) -> Dictionary:
 var area: bool = is_area(command)
 var large_ring: bool = (str(command.get("shape","")) == "ring" or str(command.get("landing_shape","")) == "ring") and float(command.get("radius",0.0)) >= 350.0
 var family: String = "large_ring" if large_ring else "area" if area else "short"
 var floor: float = 0.75 if large_ring else 0.60 if area else 0.45
 if ruleset != 2: floor = 0.55
 return _resolve(base_tell,base_lock,clampi(difficulty,0,4),floor,0.24,family,ruleset)

static func is_area(command: Dictionary) -> bool:
 return bool(command.get("warning_area",false)) or str(command.get("kind","")) in ["ground_area","charge"] or str(command.get("landing_shape","")) in ["circle","ring"]

static func _resolve(base_tell: float, base_lock: float, difficulty: int, tell_floor: float, lock_floor: float, family: String, ruleset: int) -> Dictionary:
 var tell_factor: float = TELL_FACTORS[difficulty] if ruleset==2 else 1.0
 var lock_factor: float = LOCK_FACTORS[difficulty] if ruleset==2 else 1.0
 var tell: float = maxf(tell_floor,base_tell*tell_factor) if ruleset==2 else base_tell
 var lock: float = maxf(lock_floor,base_lock*lock_factor) if ruleset==2 else base_lock
 return {"tell_seconds":tell,"lock_seconds":lock,"minimum_tell_seconds":tell_floor,"minimum_lock_seconds":lock_floor,"authored_tell_seconds":base_tell,"authored_lock_seconds":base_lock,"tell_factor":tell_factor,"lock_factor":lock_factor,"difficulty":difficulty,"family":family,"ruleset_version":ruleset}
