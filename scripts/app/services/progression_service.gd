extends RefCounted
## Progression behavior owned by this host.
## The host retains state and lifecycle; this service never owns its Node.
var host

func _init(context: Node) -> void:
	host = context

func hero_level(id: String = "") -> int:
	var hero_id = str(host.profile.get("selected_hero", "CH01")) if id.is_empty() else id
	return ContentRegistry.level_for_xp(int(host.profile.get("hero_xp", {}).get(hero_id, 0)), host._profile_ruleset())

func hero_talents(hero_id: String = "") -> Dictionary:
	var id = str(host.profile.get("selected_hero", "CH01")) if hero_id.is_empty() else hero_id
	return host.profile.get("talents", {}).get(id, {}).duplicate(true)

func set_hero_talents(allocation: Dictionary, hero_id: String = "") -> bool:
	var id = str(host.profile.get("selected_hero", "CH01")) if hero_id.is_empty() else hero_id
	if host._profile_ruleset() != host.Numbers.V2 or not host._camp_available() or id not in ProfileStore.HERO_IDS or not host.Progression.valid_talents(allocation, host.hero_level(id)): return false
	if host.hero_talents(id) == allocation: return true
	var next = host.profile.duplicate(true)
	if not next.has("talents"): next["talents"] = {}
	next.talents[id] = allocation.duplicate(true)
	return host._commit_profile(next)

func allocate_hero_talent(node: String) -> bool:
	if host._profile_ruleset() != host.Numbers.V2 or node not in host.Progression.TALENTS: return false
	var id = host.run.hero_id if host.run != null else str(host.profile.selected_hero)
	var allocation = host.hero_talents(id)
	allocation[node] = int(allocation.get(node, 0)) + 1
	if not host.Progression.valid_talents(allocation, host.hero_level(id)): return false
	if host.run == null: return host.set_hero_talents(allocation, id)
	if host.run.ruleset_version() != host.Numbers.V2 or not host.get_tree().paused or host.run.hp <= 0 or host.run.demo or host._settling or not host._pending_outcome.is_empty(): return false
	var next = host.profile.duplicate(true)
	if not next.has("talents"): next["talents"] = {}
	next.talents[id] = allocation
	if not host._save(next, host.run.receipt()): return false
	host.profile = next
	host.run.stats = host._resolved_live_stats(allocation)
	host.run.stats.branches = host.run.branches_snapshot.duplicate(true)
	host.run.max_hp = host.run.stats.max_hp
	host.run.hp = minf(host.run.hp, host.run.max_hp)
	host.run.resource = minf(host.run.resource, float(host.run.stats.resource_max))
	host.changed.emit()
	return true

func hero_branches(hero_id: String = "") -> Dictionary:
	var id = str(host.profile.selected_hero) if hero_id.is_empty() else hero_id
	if not id in ProfileStore.HERO_IDS:
		return {}
	return host.profile.get("branches", {}).get(id, {"q": "", "ultimate": ""}).duplicate(true)

func set_hero_branch(slot: String, choice: String, hero_id: String = "") -> bool:
	host.last_error = ""
	var id = str(host.profile.selected_hero) if hero_id.is_empty() else hero_id
	if not host._camp_available() or not id in ProfileStore.HERO_IDS or not slot in ["q", "ultimate"] \
		or not choice in ["A", "B", ""] or host.hero_level(id) < (18 if slot == "q" else 20):
		return false
	if host.hero_branches(id)[slot] == choice:
		return true
	var next_profile = host.profile.duplicate(true)
	next_profile.branches[id][slot] = choice
	return host._commit_profile(next_profile)

## UI identity bridge: catalog IDs remain template IDs for icon/trait lookup.
## Every returned record is detached from both the saved profile and the catalog.
func select_hero(id: String) -> bool:
	host.last_error = ""
	host.last_loadout_missing.clear()
	if not host._camp_available() or not id in ProfileStore.HERO_IDS: return false
	if host.profile.selected_hero == id: return true
	var next_profile = host.profile.duplicate(true)
	if not next_profile.has("loadout_presets"): next_profile.loadout_presets = {}
	next_profile.loadout_presets[str(host.profile.selected_hero)] = host.profile.loadout.duplicate(true)
	var desired: Dictionary = next_profile.loadout_presets.get(id, host.profile.loadout).duplicate(true)
	var missing: Array[String] = []
	for slot: String in host.equipment_slots():
		var item: String = str(desired.get(slot, ""))
		if host._profile_ruleset() == host.Numbers.V2:
			# Empty is a real choice; a different class never receives a rerolled
			# copy or silently wears an incompatible instance from the last hero.
			if not item.is_empty() and not host._camp_instance_fits(item, id):
				missing.append(slot)
				desired[slot] = ""
		elif item.is_empty() or not next_profile.equipment.has(item):
			missing.append(slot)
			desired[slot] = str(host.profile.loadout[slot])
	next_profile.selected_hero = id
	next_profile.loadout = desired
	if not host._commit_profile(next_profile): return false
	host.last_loadout_missing = missing
	return true
