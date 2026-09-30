extends RefCounted
## A small death-only reward for kills in the current unfinished room.
## The controller applies this inside its atomic settlement transaction.
const RunData = preload("res://scripts/core/run_state.gd")
const XP_PER_KILL := 2
const MAX_FIELD_XP := 18
const MAX_HERO_XP := 3600

static func calculate(run: Variant, profile: Dictionary, outcome: String) -> int:
	if outcome != "death" or (not run is RunData and not run is Dictionary): return 0
	var demo: Variant = run.get("demo")
	if demo != null and demo != false: return 0
	var expedition: Variant = run.get("expedition")
	if not expedition is Dictionary or expedition.get("phase") != "combat": return 0
	# New single-race dungeons discard unsettled field XP on death. Banked
	# hero XP is untouched; the old consolation award belongs only to v1 runs.
	var route: Variant = expedition.get("route", {})
	if route is Dictionary and route.get("dynamic_version") == 2: return 0
	# Cleared rooms have already committed their XP; defensive checking also
	# excludes a completed node if a caller supplies an inconsistent snapshot.
	if expedition.get("node_index", -1) in expedition.get("completed_nodes", []): return 0
	var kills: Variant = run.get("kills")
	var entry_kills: Variant = expedition.get("room_entry_kills")
	if not _counter(kills) or not _counter(entry_kills): return 0
	var hero: Variant = run.get("hero_id")
	var all_xp: Variant = profile.get("hero_xp")
	if not hero is String or not all_xp is Dictionary or not all_xp.has(hero): return 0
	var current_xp: Variant = all_xp[hero]
	if not _counter(current_xp) or int(current_xp) >= MAX_HERO_XP: return 0
	var unfinished_kills: int = clampi(int(kills) - int(entry_kills), 0, MAX_FIELD_XP / XP_PER_KILL)
	return mini(unfinished_kills * XP_PER_KILL, MAX_HERO_XP - int(current_xp))

static func _counter(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) >= 0.0 and float(value) <= 1_000_000_000_000.0 and float(value) == floorf(float(value))
