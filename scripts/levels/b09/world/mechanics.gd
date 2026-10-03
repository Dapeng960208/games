extends Node2D
## Room-local crystal, lantern, ice and alternating bridge state.
const Content = preload("res://scripts/levels/b09/world/content.gd")
const Skills = preload("res://scripts/levels/b09/combat/skills.gd")
const Art = preload("res://scripts/infrastructure/assets/world_art.gd")
var room: Node2D
var definition: Dictionary = {}
var clock := 0.0
var lamps: Dictionary = {}
var snow: Array[Dictionary] = []
var walls: Array[Dictionary] = []
var bridge: Dictionary = {}
var bridge_serial := 0
var _pending: Dictionary = {}
var _bridge_cursor := 0
var _floor: Node2D
var _ice_texture: Texture2D
var _environment_texture: Texture2D
var _environment_rect := Rect2()
var ice: Array[Dictionary] = []
var _scenery: Node2D
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")

func configure(host: Node2D) -> void:
	room=host
	definition=Content.room(room.layout_id)
	for lamp: Dictionary in definition.lamps:
		lamps[lamp.id]={"at":Content.point(lamp.position),"ready":0.0,"warm_until":0.0,"siphon_until":0.0}
	_floor=Node2D.new()
	_floor.z_index=-4
	_floor.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_floor)
	_floor.draw.connect(_draw_floor)
	z_index=3
	_ice_texture=Sampler.sampled("asset://b09/ice_floor/source.png")
	_environment_texture=Art.environment_texture_for("B09",room.layout_id)
	_environment_rect=Art.environment_world_rect(room.layout.arena,"B09",room.layout_id)
	# Scenery shares the actors' foot-based depth plane; mechanisms remain visible.
	_scenery=Node2D.new()
	_scenery.name="B09Scenery"
	_scenery.z_index=2
	_scenery.y_sort_enabled=true
	room.add_child(_scenery)
	for lamp: Dictionary in definition.lamps:
		if not bool(lamp.get("baked_visual",false)): _prop("warm_lamp",Content.point(lamp.position),108.0)
	for value: Array in definition.obstructions:
		var box := Content.rect(value)
		if definition.get("obstruction_kind","column")=="column" and not bool(definition.get("obstructions_baked_visual",false)):
			_prop("crystal_column",Vector2(box.get_center().x,box.end.y),90.0)

func _exit_tree() -> void:
	if is_instance_valid(_scenery): _scenery.queue_free()

func _prop(id: String, at: Vector2, height: float, region: Rect2 = Rect2(), width: float = 0.0) -> void:
	var texture := Sampler.sampled("asset://b09/"+id+"/source.png")
	if texture==null: return
	var sprite := Sprite2D.new()
	sprite.texture=texture
	if region.has_area():
		sprite.region_enabled=true
		sprite.region_rect=region
	var size: Vector2=region.size if region.has_area() else texture.get_size()
	sprite.scale=Vector2(height/size.y,height/size.y)
	if width>0: sprite.scale.x=width/size.x
	sprite.centered=false
	sprite.offset=Vector2(-size.x*0.5,-size.y)
	sprite.position=at
	_scenery.add_child(sprite)

func register_actor(actor: Node2D) -> void:
	actor.set_meta("b09_layers",int(actor.profile.get("crystal_layers",0)))
	actor.set_meta("b09_last_hit",clock)
	actor.set_meta("b09_dot_ready",0.0)
	actor.set_meta("b09_hit_roots",[])
	actor.set_meta("b09_exposed_until",0.0)

func tick(delta: float) -> void:
	if delta<=0: return
	clock+=delta
	for patch: Dictionary in ice.duplicate():
		if float(patch.until)<=clock: ice.erase(patch)
	for patch: Dictionary in snow.duplicate():
		if float(patch.until)<=clock: snow.erase(patch)
	for wall: Dictionary in walls.duplicate():
		var actor: Object=wall.actor.get_ref()
		if float(wall.until)<=clock or not _alive(actor):
			if _alive(actor) and wall.has("shatter"):
				var c: Dictionary=wall.shatter.duplicate(true)
				var owner: Object=wall.owner.get_ref()
				if _alive(owner): room.enemy_skills.emit_skill(owner,c)
			if _alive(actor): actor.queue_free()
			walls.erase(wall)
	for actor: Node2D in room.enemies.get_children():
		if not _alive(actor) or not bool(actor.profile.get("b09_candidate",false)): continue
		if actor.has_meta("b09_restore_layers") and clock>=float(actor.get_meta("b09_restore_at",0.0)):
			actor.set_meta("b09_layers",int(actor.get_meta("b09_restore_layers")))
			actor.remove_meta("b09_restore_layers")
		if actor.actor_kind=="boss": continue
		var last := float(actor.get_meta("b09_last_hit",clock))
		if clock-last>=8.0 and int(actor.get_meta("b09_layers",0))<int(actor.profile.get("crystal_layers",0)):
			actor.set_meta("b09_layers",int(actor.get_meta("b09_layers",0))+1)
			actor.set_meta("b09_last_hit",clock)
	if not _pending.is_empty():
		var actor: Object=_pending.actor.get_ref()
		if not _alive(actor) or room.input_blocked or actor.position.distance_to(Vector2(_pending.at))>68 or not room.has_line_of_sight(actor.position,_pending.at) or int(room.telemetry.player_hits)!=int(_pending.hit_serial):
			_pending.clear()
		else:
			_pending.remaining=float(_pending.remaining)-delta
			if float(_pending.remaining)<=0:
				activate_lamp(str(_pending.id))
				_pending.clear()
	if not bridge.is_empty():
		bridge.remaining=float(bridge.remaining)-delta
		if room.objective_complete: bridge.clear()
		elif float(bridge.remaining)<=0:
			if bridge.state=="warning":
				bridge.state="closed"
				bridge.remaining=4.0
				_safe_rebound()
			else: bridge.clear()
	_floor.queue_redraw()
	queue_redraw()

func interact(id: String, actor: Node2D) -> bool:
	if not lamps.has(id) or not _pending.is_empty() or not _alive(actor) or Game.run==null: return false
	var lamp: Dictionary=lamps[id]
	if clock<float(lamp.ready) or actor.position.distance_to(lamp.at)>68 or not room.has_line_of_sight(actor.position,lamp.at): return false
	_pending={"id":id,"actor":weakref(actor),"at":lamp.at,"remaining":0.6,"hit_serial":int(room.telemetry.player_hits)}
	return true

func cancel_interaction() -> void: _pending.clear()

func activate_lamp(id: String) -> bool:
	if not lamps.has(id) or clock<float(lamps[id].ready): return false
	lamps[id].ready=clock+16.0
	lamps[id].warm_until=clock+8.0
	var radius := 100.0 if clock<float(lamps[id].siphon_until) else 160.0
	for actor: Node2D in room.enemies.get_children():
		if not _alive(actor) or not bool(actor.profile.get("b09_candidate",false)) or actor.position.distance_to(lamps[id].at)>radius: continue
		var last_layer := int(actor.get_meta("b09_layers",0))==1
		if break_layer(actor) and last_layer: _barrier_broken(actor,{"damage_source":"skill","b09_lamp":true,"equipment_eligible":true,"proc_depth":0})
		if actor.brain!=null and actor.brain.has_method("current_skill"):
			var kind: String=str(actor.brain.current_skill().get("kind",""))
			if kind=="b09_reform" or (kind=="b09_shield" and room.difficulty>=4): actor.brain.interrupt(actor)
	return true

func break_layer(actor: Node2D) -> bool:
	var count := int(actor.get_meta("b09_layers",0))
	if count<=0: return false
	actor.set_meta("b09_layers",count-1)
	actor.set_meta("b09_last_hit",clock)
	if count==1:
		actor.set_meta("b09_exposed_until",clock+(4.0 if actor.actor_kind=="boss" else 2.0))
	return true

func filter_damage(actor: Node2D, amount: float, kind: StringName, context: Dictionary) -> float:
	if amount<=0 or not bool(actor.profile.get("b09_candidate",false)): return amount
	var layers := int(actor.get_meta("b09_layers",0))
	var reduction := 1.0-0.08*layers
	var dot := bool(context.get("dot",false)) or str(kind) in ["burn","bleed","corrosion"]
	actor.set_meta("b09_last_hit",clock)
	var root := str(context.get("root_event_id",context.get("attack_id",context.get("cast_id",""))))
	var roots: Array=actor.get_meta("b09_hit_roots",[])
	if dot:
		if clock>=float(actor.get_meta("b09_dot_ready",0.0)):
			break_layer(actor)
			actor.set_meta("b09_dot_ready",clock+1.0)
	elif root.is_empty() or root not in roots:
		break_layer(actor)
		if not root.is_empty():
			roots.append(root)
			if roots.size()>32: roots.pop_front()
			actor.set_meta("b09_hit_roots",roots)
	if layers==0 and clock<float(actor.get_meta("b09_exposed_until",0.0)) and (actor.actor_kind=="boss" or (actor.enemy_id=="B09-M13" and room.difficulty>=4)): reduction*=1.15
	if layers>0 and int(actor.get_meta("b09_layers",0))==0: _barrier_broken(actor,context)
	return amount*reduction

func _barrier_broken(actor: Node2D, context: Dictionary) -> void:
	if not is_instance_valid(room.player) or not bool(context.get("equipment_eligible",false)) or int(context.get("proc_depth",1))!=0: return
	var event := context.duplicate(true)
	event.merge({"target":actor,"crystal_broken":true},true)
	room.player.loadout.event("b09_barrier_broken",event)

func allies(caster: Node2D) -> Array:
	var result: Array=[]
	for actor: Node2D in room.enemies.get_children():
		if actor==caster or not _alive(actor) or actor.actor_kind!="enemy" or not bool(actor.profile.get("b09_candidate",false)) or actor.owner_enemy!=null or bool(actor.get_meta("b09_no_support",false)): continue
		if actor.position.distance_to(caster.position)<=260 and int(actor.get_meta("b09_layers",0))<3: result.append(actor)
	result.sort_custom(func(a: Node2D,b: Node2D) -> bool: return a.position.distance_squared_to(caster.position)<b.position.distance_squared_to(caster.position))
	return result.slice(0,2)

func is_ice(at: Vector2) -> bool:
	for patch: Dictionary in snow:
		if at.distance_to(patch.at)<=float(patch.radius): return false
	for lamp: Dictionary in lamps.values():
		if clock<float(lamp.warm_until) and at.distance_to(lamp.at)<=(100.0 if clock<float(lamp.siphon_until) else 160.0): return false
	for patch: Dictionary in ice:
		if patch.rect.has_point(at): return true
	for value: Array in definition.ice_rects:
		if Content.rect(value).has_point(at): return true
	return false

func movement_velocity(actor: Node2D, input_motion: Vector2, desired: Vector2, delta: float) -> Vector2:
	if not is_ice(actor.position) or actor.dash_remaining>0 or not room.controls_enabled():
		cancel_glide(actor)
		return desired
	if not input_motion.is_zero_approx():
		actor.set_meta("b09_glide_direction",input_motion.normalized())
		actor.set_meta("b09_glide_remaining",0.25)
		return desired
	var remaining := float(actor.get_meta("b09_glide_remaining",0.0))
	if remaining<=0: return desired
	var step := minf(delta,remaining)
	actor.set_meta("b09_glide_remaining",maxf(0,remaining-delta))
	var scale := clampf(float(actor.loadout.modifiers().get("b09_glide_distance_scale",1.0)),0.5,1.0)
	return desired+Vector2(actor.get_meta("b09_glide_direction",Vector2.ZERO))*160.0*scale*step/maxf(delta,0.001)

func cancel_glide(actor: Node2D) -> void:
	actor.set_meta("b09_glide_remaining",0.0)
	actor.set_meta("b09_glide_direction",Vector2.ZERO)

func request_bridge(id: String = "", warning: float = 2.0) -> bool:
	if not bridge.is_empty() or definition.bridges.is_empty() or room.objective_complete: return false
	var index: int = _bridge_cursor%definition.bridges.size()
	if not id.is_empty():
		for i in definition.bridges.size():
			if definition.bridges[i].id==id: index=i
	var selected: Dictionary=definition.bridges[index]
	_bridge_cursor=index+1
	bridge_serial+=1
	bridge={"id":selected.id,"rect":Content.rect(selected.rect),"state":"warning","remaining":warning,"serial":bridge_serial}
	if selected.has("polygon"): bridge["polygon"]=Content.polygon(selected.polygon)
	if selected.has("safe_landings"):
		var landings: Array[Vector2]=[]
		for at: Array in selected.safe_landings: landings.append(Content.point(at))
		bridge["safe_landings"]=landings
	return true

func blocks_ground(at: Vector2, radius: float) -> bool:
	for box: Rect2 in navigation_bounds():
		if box.grow(radius).has_point(at): return true
	return false

func navigation_bounds() -> Array[Rect2]:
	var result: Array[Rect2]=[]
	if not bridge.is_empty() and bridge.state=="closed": result.append(bridge.rect)
	for wall: Dictionary in walls:
		if _alive(wall.actor.get_ref()): result.append(wall.rect)
	return result

func _safe_rebound() -> void:
	var actor: Node2D=room.player
	if not _alive(actor) or not Rect2(bridge.rect).grow(Balance.PLAYER_RADIUS).has_point(actor.position): return
	var box: Rect2=bridge.rect
	var margin := Balance.PLAYER_RADIUS+6.0
	var candidates: Array[Vector2]=[Vector2(box.position.x-margin,actor.position.y),Vector2(box.end.x+margin,actor.position.y),Vector2(actor.position.x,box.position.y-margin),Vector2(actor.position.x,box.end.y+margin)]
	for at: Vector2 in bridge.get("safe_landings",[]): candidates.append(at)
	candidates.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.distance_squared_to(actor.position)<b.distance_squared_to(actor.position))
	for at: Vector2 in candidates:
		if not room.valid_ground(at,Balance.PLAYER_RADIUS): continue
		actor.position=at
		actor.cancel_actions()
		cancel_glide(actor)
		var ordinary := Skills.profile("B09-M01",int(definition.enemy_level),room.difficulty)
		var amount := minf(float(ordinary.damage)*0.6,float(Game.run.stats.max_hp)*0.08)
		actor.receive_damage(amount,at,{"damage_type":"true","b09_environment":true,"attack_id":"b09_bridge:"+str(bridge.serial)})
		return

func constrain(c: Dictionary, actor: Node2D) -> Dictionary:
	var result := c.duplicate(true)
	if c.kind=="b09_bridge":
		if not bridge.is_empty() or definition.bridges.is_empty(): return {}
		var selected: Dictionary=definition.bridges[_bridge_cursor%definition.bridges.size()]
		result["b09_bridge_id"]=selected.id
		result.target=Content.rect(selected.rect).get_center()
		result["radius"]=maxf(Content.rect(selected.rect).size.x,Content.rect(selected.rect).size.y)*0.5
		result["targets"]=[result.target]
		if room.difficulty>=2:
			# A closure rectangle is only the narrow gate across a painted bridge.
			# The warning and frozen end waves use its authored banks/road shoulders.
			var ends: Array=selected.get("wave_ends",selected.get("safe_landings",[]))
			if ends.size()==2:
				for at: Array in ends: result.followups.append(Skills.area(result,Content.point(at),55,60 if actor.actor_kind=="boss" else 30,0.0))
			else:
				var box := Content.rect(selected.rect)
				for side in [-1,1]: result.followups.append(Skills.area(result,box.get_center()+Vector2(side*(box.size.x*0.5+40),0),55,60 if actor.actor_kind=="boss" else 30,0.0))
	if c.kind=="charge" and bool(c.get("b09_stop_on_snow",false)):
		var distance := float(c.travel_distance)
		for step in range(1,int(ceil(distance/8))+1):
			var at := Vector2(c.origin)+Vector2(c.direction)*minf(distance,step*8.0)
			if not is_ice(at) or not room.valid_ground(at,float(actor.navigation_radius)):
				result.travel_distance=minf(distance,maxf(0,(step-1)*8.0))
				result.target=Vector2(c.origin)+Vector2(c.direction)*float(result.travel_distance)
				if actor.enemy_id=="B09-M09": result.followups=[]
				break
	return result

func warm_at(at: Vector2) -> bool:
	for lamp: Dictionary in lamps.values():
		if clock<float(lamp.warm_until) and at.distance_to(lamp.at)<=160: return true
	return false

func expose(actor: Node2D, seconds: float, restore_layers: bool = false) -> void:
	if restore_layers:
		actor.set_meta("b09_restore_layers",int(actor.get_meta("b09_layers",0)))
		actor.set_meta("b09_restore_at",clock+seconds)
	actor.set_meta("b09_layers",0)
	actor.set_meta("b09_exposed_until",clock+seconds)
	actor.set_meta("b09_last_hit",clock)

func _alive(actor: Object) -> bool:
	if not is_instance_valid(actor) or actor.is_queued_for_deletion(): return false
	if actor==room.player: return Game.run!=null and Game.run.hp>0
	return actor.has_method("is_alive") and actor.is_alive()

func _draw_floor() -> void:
	# Static snow, ice, bridges and the court belong to the room painting.
	# Only real temporary mechanics draw above that shared environment.
	var overlays: Array[Rect2]=[]
	for patch: Dictionary in ice:
		overlays.append(patch.rect)
		if _ice_texture!=null: _floor.draw_texture_rect(_ice_texture,patch.rect,false,Color(1,1,1,0.5))
		else: _floor.draw_rect(patch.rect,Color(0.65,0.87,0.95,0.45))
		_floor.draw_rect(patch.rect,Color(0.48,0.71,0.89,0.55),false,1.5)
	for patch: Dictionary in snow:
		overlays.append(Rect2(Vector2(patch.at)-Vector2.ONE*float(patch.radius),Vector2.ONE*float(patch.radius)*2.0))
		_floor.draw_circle(patch.at,patch.radius,Color(0.97,0.96,1.0,0.5))
	for lamp: Dictionary in lamps.values():
		if clock<float(lamp.warm_until):
			var radius := 100.0 if clock<float(lamp.siphon_until) else 160.0
			overlays.append(Rect2(Vector2(lamp.at)-Vector2.ONE*radius,Vector2.ONE*radius*2.0))
			_floor.draw_circle(lamp.at,radius,Color(1.0,0.84,0.53,0.18))
			_floor.draw_arc(lamp.at,radius,0,TAU,64,Color(0.94,0.77,0.47,0.65),1.5,true)
	# Restore only gap pixels touched by temporary floor overlays. Untouched
	# landscape retains the shared backdrop and its approved native details.
	if not overlays.is_empty() and definition.get("obstruction_kind","column")=="gap":
		for value: Array in definition.obstructions:
			var box := Content.rect(value)
			for overlay: Rect2 in overlays:
				var covered := box.intersection(overlay)
				if covered.has_area(): _restore_painted_ground(covered)
	if not bridge.is_empty():
		var box: Rect2=bridge.rect
		var closed: bool=bridge.state=="closed"
		var tint := Color(0.4,0.38,0.61,0.22) if closed else Color(0.95,0.65,0.45,0.24)
		var border := Color("756287") if closed else Color("ba7d66")
		var outline: PackedVector2Array=bridge.get("polygon",PackedVector2Array())
		if outline.size()>=3:
			_floor.draw_colored_polygon(outline,tint)
			for index in outline.size(): _floor.draw_line(outline[index],outline[(index+1)%outline.size()],border,2.0,true)
		else:
			_floor.draw_rect(box,tint)
			_floor.draw_rect(box,border,false,2.0)
		# The closed state is an impassable crystal gate on the real footprint.
		# Preserve the painted bridge; never invent a rectangular chasm over it.
		if closed:
			_floor.draw_rect(box,Color(0.4,0.38,0.61,0.5))
			_floor.draw_rect(box,border,false,4.0)

func _restore_painted_ground(box: Rect2) -> void:
	if _environment_texture==null or not _environment_rect.has_area(): return
	var clipped := box.intersection(_environment_rect)
	if not clipped.has_area(): return
	var native := _environment_texture.get_size()
	var source := Rect2((clipped.position-_environment_rect.position)/_environment_rect.size*native,clipped.size/_environment_rect.size*native)
	_floor.draw_texture_rect_region(_environment_texture,clipped,source)

func _draw() -> void:
	for actor: Node2D in room.enemies.get_children():
		if not _alive(actor) or not bool(actor.profile.get("b09_candidate",false)): continue
		for i in int(actor.get_meta("b09_layers",0)):
			var at := actor.position+Vector2((i-1)*11,-14)
			draw_colored_polygon(PackedVector2Array([at+Vector2(0,-7),at+Vector2(5,0),at+Vector2(0,7),at+Vector2(-5,0)]),Color("b2e5fb"))
	for wall: Dictionary in walls:
		draw_rect(wall.rect,Color("9dbbea"))
		draw_rect(wall.rect,Color("6e6996"),false,2.0)
