extends Node
## Actual room/player/controllers exercise automatic beacons without E input.
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const Props = preload("res://scripts/presentation/world/room_props.gd")
const Generator = preload("res://scripts/gameplay/world/room_generator.gd")
const Layouts = preload("res://scripts/domain/world/room_layouts.gd")
const PropArt = preload("res://scripts/infrastructure/assets/world_prop_art.gd")

var checks := 0
var failures := 0
var room: RoomController

func _ready() -> void:
	call_deferred("run_checks")
	get_tree().create_timer(60.0).timeout.connect(func(): push_error("Beacon acceptance timed out"); get_tree().quit(1))

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func fixture(hero: String) -> void:
	if is_instance_valid(room): room.free()
	Game.run.hero_id = hero
	Game.run.level = 1
	Game.run.stats = StatResolver.resolve(hero,1,{}, {})
	Game.run.max_hp = float(Game.run.stats.max_hp)
	Game.run.hp = Game.run.max_hp
	Game.run.shield = 0.0
	Game.run.resource = float(Game.run.stats.resource_max)
	room = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = true
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = room.layout.entry

func effect(index: int, kind: String) -> Dictionary:
	var item: Dictionary = room.enemy_props.props[index]
	item.merge(Props.BUFFS[kind].duplicate(true), true)
	item.merge({"effect":kind,"used":false,"available":true,"cooldown":0.0,"remaining":0.0,"armed":true},true)
	return item

func approach(item: Dictionary) -> void:
	room.player.position = item.position
	room.enemy_props.update(0.01)

func run_checks() -> void:
	AudioServer.set_bus_mute(0,true)
	if not Game.profile_path.contains("test_buff_beacons"):
		push_error("Beacon acceptance requires isolated test_buff_beacons profile")
		get_tree().quit(2)
		return
	check(Game.new_profile() and Game.start_run(),"isolated beacon run starts")
	if Game.run == null: get_tree().quit(1); return
	for hero: String in ["CH01","CH02","CH03"]:
		fixture(hero)
		_test_restoration(hero)
		_test_timed_buffs(hero)
		_test_recharge_and_pause(hero)
	_test_deterministic_positions_and_functions()
	_test_obstacles_and_reset()
	_test_authored_beacon_assets()
	if is_instance_valid(room):
		check(await room.combat_audio.wait_for_cleanup(),"beacon fixture audio cleans up")
		room.free()
	Game.finish_run("abandoned")
	await get_tree().process_frame
	print("BUFF BEACONS: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)

func _test_restoration(hero: String) -> void:
	var prop: Node2D = room.enemy_props
	check(prop.props.size()==3,hero+" has three fixed non-solid beacons")
	var layer: Node2D = room.get_node_or_null("BeaconBodies")
	check(is_instance_valid(layer) and layer.z_index==room.player.z_index and layer.y_sort_enabled,hero+" beacon bodies share the actors' depth plane")
	if is_instance_valid(layer):
		check(layer.get_child_count()==3,hero+" one depth-sorted body per beacon")
		for index: int in layer.get_child_count():
			check(layer.get_child(index).position==prop.props[index].position,hero+" beacon sorting uses its fixed contact foot")
	var hp: Dictionary = effect(0,"heal")
	Game.run.hp = Game.run.max_hp * 0.5
	var before: float = Game.run.hp
	room.player.position = hp.position + Vector2(73,0)
	prop.update(0.01)
	check(Game.run.hp==before and not hp.used,hero+" outside radius cannot heal")
	approach(hp)
	check(is_equal_approx(Game.run.hp,before+Game.run.max_hp*.25) and hp.used,hero+" approach automatically restores 25% HP without E")
	check(prop.nearest_interaction(room.player.position).is_empty() and not prop.interact(hp.id,room.player).success,hero+" no beacon E target or manual activation")
	before = Game.run.hp
	for index: int in 20: prop.update(0.01)
	check(Game.run.hp==before and hp.activations==1,hero+" standing in ring grants exactly once")
	room.player.position = hp.position + Vector2(90,0)
	prop.update(0.01)
	approach(hp)
	check(Game.run.hp==before and hp.activations==1,hero+" early re-entry does not grant again")
	hp = effect(0,"heal")
	Game.run.hp = Game.run.max_hp
	var activations: int = hp.activations
	approach(hp)
	check(not hp.used and hp.activations==activations and hp.available,hero+" full HP keeps beacon ready")
	Game.run.hp -= 1.0
	prop.update(0.01)
	check(is_equal_approx(Game.run.hp,Game.run.max_hp) and hp.used,hero+" restoration clamps to actual HP cap")
	var energy: Dictionary = effect(1,"resource")
	var maximum: float = float(Game.run.stats.resource_max)
	Game.run.resource = maximum
	approach(energy)
	check(not energy.used and Game.run.resource==maximum,hero+" full class resource does not consume beacon")
	Game.run.resource = maximum * 0.10
	prop.update(0.01)
	check(is_equal_approx(Game.run.resource,maximum*.40) and energy.used,hero+" correct class resource restored by 30% of its cap")
	energy = effect(1,"resource")
	Game.run.resource = maximum-1.0
	approach(energy)
	check(is_equal_approx(Game.run.resource,maximum),hero+" class resource cannot overflow")
	hp = effect(0,"heal")
	Game.run.hp = 0.0
	approach(hp)
	check(Game.run.hp==0.0 and not hp.used,hero+" dead actor cannot revive from beacon")
	Game.run.hp = Game.run.max_hp

func _test_timed_buffs(hero: String) -> void:
	var prop: Node2D = room.enemy_props
	prop.clear()
	check(prop.configure(room,room.layout),hero+" reset clears previous beacon effects")
	var damage: Dictionary = effect(0,"damage")
	var guard: Dictionary = effect(1,"guard")
	var haste: Dictionary = effect(2,"haste")
	var base_attack: float = room.player.stat("damage_bonus",0.0)
	var base_speed: float = room.player.stat("move_speed",220.0)
	approach(damage)
	check(is_equal_approx(room.player.stat("damage_bonus",0.0),minf(.60,base_attack+.20)),hero+" valor passes through real damage modifier")
	approach(guard)
	check(is_equal_approx(Game.run.shield,Game.run.max_hp*.25) and room.player.status.guards.has(Props.GUARD_SOURCE),hero+" guardian grants real synchronized shield source")
	approach(haste)
	check(room.player.stat("move_speed",220.0)>base_speed and is_equal_approx(prop.move_multiplier(),1.15),hero+" swiftness affects actual movement stat")
	check(prop.active_buffs().size()==3,hero+" real HUD snapshots contain three timed effects")
	var old_attack: float = prop.damage_bonus()
	check(prop.grant_buff("damage",room.player) and prop.damage_bonus()==old_attack,hero+" same effect refresh never multiplies stacks")
	room.player.position = room.layout.entry
	prop.update(15.0)
	room.player.status.tick(15.0)
	Game.run.shield = room.player.status.shield()
	check(prop.active_buffs().is_empty() and Game.run.shield==0.0,hero+" timed effects really expire")

func _test_recharge_and_pause(hero: String) -> void:
	var prop: Node2D = room.enemy_props
	prop.configure(room,room.layout)
	var item: Dictionary = effect(0,"damage")
	var at: Vector2 = item.position
	approach(item)
	var cooldown: float = item.cooldown
	var remaining: float = prop.buffs.damage.remaining
	get_tree().paused = true
	prop.update(20.0)
	check(item.cooldown==cooldown and prop.buffs.damage.remaining==remaining,hero+" pause freezes refresh and buff timers")
	var other: Dictionary = effect(1,"heal")
	Game.run.hp = Game.run.max_hp*.5
	approach(other)
	check(not other.used and is_equal_approx(Game.run.hp,Game.run.max_hp*.5),hero+" paused proximity cannot grant")
	get_tree().paused = false
	room.player.position = at
	prop.update(Props.BEACON_RECHARGE)
	check(item.position==at and item.generation==1 and not item.used and item.available,hero+" 45-second refresh retains fixed position and offers random function")
	check(item.effect in Props.BEACON_EFFECTS and not item.armed,hero+" new ready function requires next approach")
	var count: int = item.activations
	prop.update(0.5)
	check(item.activations==count,hero+" standing during refresh does not farm repeated grant")
	room.player.position = at+Vector2(90,0)
	prop.update(0.01)
	check(item.armed,hero+" leaving ring rearms refreshed beacon")
	Game.run.hp = Game.run.max_hp*.5
	Game.run.resource = 0.0
	approach(item)
	check(item.used and item.activations==count+1,hero+" reapproach triggers exactly one refreshed function")

func _sequence(seed_value: int) -> Array:
	var prop: Node2D = room.enemy_props
	var layout: Dictionary = Generator.generate("L05",seed_value)
	prop.configure(room,layout)
	room.player.position = layout.entry
	var values: Array = []
	for iteration: int in 12:
		for item: Dictionary in prop.props:
			values.append([item.position,item.effect,item.generation])
			item.cooldown = 0.01
			item.used = true
		prop.update(0.02)
	return values

func _test_deterministic_positions_and_functions() -> void:
	var first: Array = _sequence(18842)
	var replay: Array = _sequence(18842)
	check(first==replay,"seed reproduces fixed positions and entire refresh function sequence")
	var different: Array = _sequence(4421)
	check(first!=different,"different room seed produces another exploration setup")
	var found: Dictionary = {}
	for entry: Array in first:
		found[entry[1]] = true
	check(found.size()==5,"seeded refresh sequence actually includes all five functional types")
	for index: int in first.size():
		check(first[index][0]==first[index%3][0],"refresh never relocates beacon "+str(index))

func _test_obstacles_and_reset() -> void:
	var prop: Node2D = room.enemy_props
	var layout: Dictionary = Generator.generate("L05",18842)
	room.layout = layout
	room.obstructions.assign(layout.obstructions)
	prop.configure(room,layout)
	var initial_obstacles: Array = prop.collision_rects()
	for item: Dictionary in prop.props:
		check(Layouts.clear_for_actor(layout,item.position,35.0),"beacon ground point is clear for player")
		for danger: Dictionary in layout.get("hazard_zones",[]):
			check(not danger.get("rect",Rect2()).grow(35).has_point(item.position),"beacon never occupies hazard")
	check(initial_obstacles==room.obstructions,"three beacons add no collision obstacles")
	var blocked: Dictionary = effect(0,"damage")
	room.player.position = blocked.position-Vector2(60,0)
	var wall := Rect2(blocked.position-Vector2(35,15),Vector2(10,30))
	prop.layout.obstructions.append(wall)
	room.obstructions.append(wall)
	prop.update(.01)
	check(not blocked.used,"72-unit proximity cannot grant through a solid wall")
	prop.layout.obstructions.erase(wall)
	room.obstructions.erase(wall)
	approach(blocked)
	room.player.status.grant_guard(10,60,"other_source",Game.run.max_hp)
	check(prop.grant_buff("guard",room.player),"room source guard granted before reset")
	check(prop.configure(room,layout),"room reconfigure succeeds")
	check(prop.active_buffs().is_empty() and not room.player.status.guards.has(Props.GUARD_SOURCE) and room.player.status.guards.has("other_source"),"room reset clears only own buffs and shields")
	for item: Dictionary in prop.props:
		check(item.cooldown==0.0 and item.generation==0 and item.activations==0 and not item.used,"room reset begins fresh beacon state")
	prop.clear()
	check(prop.props.is_empty() and prop.buffs.is_empty(),"room clear removes all beacon entities and timers")

func _test_authored_beacon_assets() -> void:
	for kind: String in ["heal","resource","guard","haste","damage","dormant"]:
		var key: String = "beacon_"+kind
		var definition: Dictionary = PropArt.definition_for_asset(key)
		var texture: Texture2D = PropArt.texture_for_asset(key)
		check(not definition.is_empty() and texture!=null,key+" has fresh authored atlas art")
		if definition.is_empty() or texture==null: continue
		var source: Rect2 = definition.source
		var foot: Vector2 = definition.foot
		var ground: Rect2 = definition.ground
		check(Rect2(Vector2.ZERO,texture.get_size()).has_point(foot),key+" contact foot lies inside its artwork")
		check(absf(foot.x-source.size.x*.5)<=source.size.x*.10,key+" contact foot aligns with the drawn pedestal centre")
		check(ground.has_area() and Rect2(Vector2.ZERO,texture.get_size()).encloses(ground),key+" measured base footprint stays inside its cropped artwork")
		var at := Vector2(700,600)
		var bounds: Rect2 = PropArt.bounds_at(key,at,Vector2(78,90))
		var scale: float = PropArt.fitted_scale(key,Vector2(78,90))
		check((bounds.position+foot*scale).is_equal_approx(at),key+" scaled painted contact remains at the fixed beacon position")
