extends RefCounted
## First-four biome traits decorate existing native relic channels. No packets,
## reservations, equipment events or rewards are created by this adapter.

const STATE_META: StringName = &"race_relic_state"
const ALIASES := {"RL01":"split","RL02":"ember","RL03":"arc"}
const SOLAR_ICD := 3.0
const CLOSE_RANGE := 160.0
const PREFIX := {"B01":"晴辉","B02":"琥珀","B03":"墓灯","B04":"战寨"}
const PREFIX_EN := {"B01":"Sunward","B02":"Amber","B03":"Gravelight","B04":"Warchief"}
const MATERIALS := {"B01":"白金机关与太阳晶核","B02":"琥珀虫壳与晶质虫翼","B03":"墓灯骨饰与南瓜灵晶","B04":"红岩、骨刻与部族铜饰"}
const MATERIALS_EN := {"B01":"Ivory-gold clockwork and sun crystal","B02":"Amber chitin and crystal insect wings","B03":"Gravelight bonework and pumpkin spirit crystal","B04":"Redstone, carved bone and tribal brass"}
# Completed category art remains a fallback until the canonical race bank binds
# these stable item IDs. The UI consumes the real cached AtlasTexture.
const ART_ITEMS := {"B01":"EQ03","B02":"EQ05","B03":"EQ07","B04":"EQ09"}
const Equipment = preload("res://scripts/ui/equipment_art.gd")

static func biome_id(room: Node) -> String:
	if not is_instance_valid(room): return ""
	var context: Variant = room.get("expedition_context")
	if not context is Dictionary or context.is_empty(): return ""
	var id := str(context.get("biome_id",""))
	return id if PREFIX.has(id) else ""

static func _game(room: Node) -> Node:
	return room.get_node_or_null("/root/Game") if is_instance_valid(room) else null

static func owned(room: Node, channel: String) -> bool:
	var game := _game(room)
	if game == null or game.run == null: return false
	return game.run.relics.has(channel) or game.run.relics.has({"split":"RL01","ember":"RL02","arc":"RL03"}.get(channel,""))

static func original(context: Dictionary) -> bool:
	return bool(context.get("original_basic",false)) and bool(context.get("equipment_eligible",false)) and int(context.get("proc_depth",0)) == 0 and not str(context.get("root_event_id","")).is_empty()

static func reset_room(room: Node) -> void:
	if is_instance_valid(room) and room.has_meta(STATE_META): room.remove_meta(STATE_META)

static func confirmed_original_hit(room: Node, context: Dictionary) -> float:
	if biome_id(room) != "B01" or not owned(room,"arc") or not original(context): return 0.0
	var game := _game(room)
	var state: Dictionary = room.get_meta(STATE_META,{"hits":0,"roots":{},"solar_at":-INF})
	var roots: Dictionary = state.get("roots",{})
	var root := str(context.root_event_id)
	if roots.has(root): return 0.0
	roots[root] = true
	while roots.size() > 256: roots.erase(roots.keys()[0])
	state.roots = roots
	state.hits = int(state.get("hits",0))+1
	var now := maxf(0.0,float(room.get("elapsed")))
	var proc := int(state.hits)%3 == 0 and now-float(state.get("solar_at",-INF)) >= SOLAR_ICD
	if proc: state.solar_at = now
	room.set_meta(STATE_META,state)
	if not proc: return 0.0
	var before: float = game.run.resource
	if int(game.run.stats.get("ruleset_version", 1)) == 2:
		room.player.restore_class_resource(10.0)
	else:
		game.restore_resource(1.0)
	return maxf(0.0,game.run.resource-before)

static func native_duration(room: Node, duration: float) -> float:
	return duration*1.20 if biome_id(room) == "B02" and owned(room,"ember") else duration

static func guard_multiplier(room: Node) -> float:
	var game := _game(room)
	if biome_id(room) == "B03" and owned(room,"arc") and game != null and game.run != null and game.run.max_hp > 0.0 and game.run.hp < game.run.max_hp*.35:
		return 1.20
	return 1.0

static func split_multiplier(room: Node, at: Vector2) -> float:
	return 1.10 if biome_id(room) == "B04" and owned(room,"split") and is_instance_valid(room.get("player")) and room.player.position.distance_to(at) <= CLOSE_RANGE else 1.0

static func decorate(base: Dictionary, hero: String, relic_id: String, biome: String) -> Dictionary:
	if not PREFIX.has(biome): return base
	var out := base.duplicate(true)
	var channel := str(ALIASES.get(relic_id,relic_id))
	var english := Words.locale == "en"
	var material: String = (MATERIALS_EN if english else MATERIALS)[biome]
	out.name = str((PREFIX_EN if english else PREFIX)[biome])+" · "+str(base.name)
	out.material = material
	out.biome_id = biome
	out.art_item = ART_ITEMS[biome]
	out.texture = Equipment.texture(str(out.art_item))
	var race_effect := ""
	if biome == "B01" and channel == "arc":
		race_effect = "Every third confirmed basic-hit root restores 1 resource; 3s internal cooldown." if english else "每第3次有效普攻命中回复1点职业资源，内置冷却3秒。"
	elif biome == "B02" and channel == "ember":
		race_effect = "This relic's original basic-hit damage-over-time lasts 20% longer." if english else "该遗物由原始普攻施加的持续伤害状态时长延长20%。"
	elif biome == "B03" and channel == "arc" and hero == "CH01":
		race_effect = "Below 35% HP, the existing counterweight guard is 20% stronger; duration and refresh rules remain unchanged." if english else "生命低于35%时，该回震护盾量提高20%，时长与刷新规则不变。"
	elif biome == "B04" and channel == "split":
		race_effect = "A split triggered within 160 of the hero deals 10% more damage." if english else "在角色160范围内触发的裂地、分流或回响伤害提高10%。"
	out.race_trait = race_effect
	out.description = str(base.description)+"\n"+material+("\n"+race_effect if not race_effect.is_empty() else "")
	return out
