extends RefCounted
## Current expedition objectives are short combat counterplays. Historical
## non-expedition fixtures keep their original biome modules and mechanics.
const ConstructHive = preload("res://scripts/world/first_four_construct_hive.gd")
const GraveOrc = preload("res://scripts/world/first_four_grave_orc.gd")
var host: Node2D
var leaf: RefCounted
var biome_id := ""
var variant := 0

func configure(next_host: Node2D) -> void:
	host = next_host
	biome_id = str(host.definition.get("biome_id","B01"))
	variant = (int(str(host.room_id).trim_prefix("L"))-1)%6
	var count: int = int(host.definition.get("expedition_objective_count",2+variant%2))
	host.required_count = clampi(count,2,3)
	leaf = ConstructHive.new() if biome_id in ["B01","B02"] else GraveOrc.new()
	leaf.configure(host,biome_id,variant,host.required_count)

func tick(delta: float) -> void:
	if leaf!=null: leaf.tick(delta)

func interact(id: String, actor: Node2D) -> bool:
	return leaf!=null and leaf.interact(id,actor)

func on_target_hit(id: String, context: Dictionary) -> void:
	if leaf!=null: leaf.on_target_hit(id,context)

func on_target_destroyed(id: String) -> void:
	if leaf!=null: leaf.on_target_destroyed(id)

func notify_enemy_death(enemy: Node2D) -> void:
	if leaf!=null: leaf.notify_enemy_death(enemy)

func notify_charge_impact(caster: Node2D, from: Vector2, to: Vector2) -> Dictionary:
	return leaf.notify_charge_impact(caster,from,to) if leaf!=null else {"success":false}

func blocks_dash() -> bool: return false

func encounter_directive(_index: int) -> Dictionary: return {}

func navigation_target() -> Dictionary:
	return leaf.navigation_target() if leaf!=null else {}

func status_text() -> String:
	return leaf.status_text() if leaf!=null else ""

func status_text_en() -> String:
	return leaf.status_text_en() if leaf!=null else ""

func draw_world(canvas: Node2D) -> void:
	if leaf!=null and leaf.has_method("draw_world"): leaf.draw_world(canvas)
