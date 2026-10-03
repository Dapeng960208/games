extends "res://scripts/gameplay/world/room_controller.gd"
## Isolated scene adapter reusing real player abilities, damage and projectiles.
## No production registration, rewards, settlement, saves or borrowed room art.
const Gate = preload("res://scripts/levels/b08/candidate_gate.gd")
const SkyGeometry = preload("res://scripts/levels/b08/geometry.gd")
const SkyContent = preload("res://scripts/levels/b08/content.gd")
const SkyNumbers = preload("res://scripts/levels/b08/numbers.gd")
const SkyActor = preload("res://scripts/levels/b08/enemy_actor.gd")
const SkyBrain = preload("res://scripts/levels/b08/enemy_brain.gd")
const RoomPainting = preload("res://scripts/levels/b08/presentation/room_art_mapping.gd")
const ExistingHUD = preload("res://scripts/levels/b08/presentation/hud_host.gd")
var painted_mapping
var candidate_ui: Node
var wind = preload("res://scripts/levels/b08/wind_state.gd").new()
var harbor = preload("res://scripts/levels/b08/harbor_runtime.gd").new()
var _authored_waves: Array = []
var _next_wave := 0
var _wave_delay := 3.0
var warnings: Dictionary = {}
var feathers: Array = []
var shot_serial := 0
var _grid := AStarGrid2D.new()
var _channel_lane := ""
var _channel_hp := 0.0
var _hud: Label
var _flag: EnemyActor
var _started := false
var sky_environment: Node2D
var sky_projectile_art: RefCounted
var sky_interactions: Node2D
signal shutdown_ready
var shutdown_started := false
var shutdown_done := false
var shutdown_clean := false
var _quit_requested := false
var _lifecycle_frames := -1

func argument(key: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"+key+"="): return arg.get_slice("=",1)
	return fallback
func _ready() -> void:
	if not Gate.enabled(): push_error("B08 requires debug and isolated candidate arguments"); get_tree().quit(2); return
	if Game.run!=null: Game.reload_profile()
	var hero := argument("hero","CH01")
	difficulty = clampi(int(argument("difficulty","0")),0,4)
	if not Game.start_demo(hero,difficulty,{},true): push_error("B08 isolated demo rejected"); get_tree().quit(2); return
	Game.run.stats["crit_policy_version"] = 1
	Game.run.stats["crit_chance"] = .25
	Game.run.stats["crit_multiplier"] = 2.0
	layout_id = argument("room","L43")
	if SkyContent.room(layout_id).is_empty(): layout_id = "L43"
	spawn_enabled = false
	get_tree().auto_accept_quit = false
	_lifecycle_frames = int(argument("b08-quit-after-frames","-1"))
	super._ready()
	if not configuration_ready or not is_instance_valid(player):
		push_error("B08 room rejected: "+configuration_error)
		Game.reload_profile()
		get_tree().quit(2)
		return
	_started = true
	harbor.configure(self)
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(20,16)
	_hud.add_theme_font_size_override("font_size",18)
	_hud.add_theme_font_override("font",fx_font)
	layer.add_child(_hud)
	_open_room(layout_id)

func load_room_layout(id: String, _room_difficulty: int = -1, _seed_override: int = -1) -> bool:
	if SkyContent.room(id).is_empty(): return false
	layout_id = id
	layout = {"id":id,"room_id":id,"blueprint_room_id":id,"biome_id":"B08","name":SkyContent.room(id).name,"entry":SkyGeometry.point(SkyGeometry.ENTRY[id]),"exit":SkyGeometry.point(SkyGeometry.EXIT[id]),"arena":Rect2(0,0,1624,1044),"props":[],"decorations":[],"encounters":[]}
	ARENA = layout.arena
	exit_position = layout.exit
	relic_positions = {}
	painted_mapping=null
	configuration_ready=false
	if RoomPainting.requested(id):
		var mapping:=RoomPainting.new()
		if not mapping.configure(id,ARENA):
			configuration_error=str(mapping.errors)
			return false
		painted_mapping=mapping
	configuration_ready = true
	_build_navigation()
	return true
func _biome_id() -> String: return "B08"
func _create_ground_canvases() -> void:
	_floor_canvas = Node2D.new()
	_floor_canvas.z_index = -3
	add_child(_floor_canvas)
	_floor_canvas.draw.connect(_draw_floor)
func painting_ready() -> bool: return painted_mapping!=null and painted_mapping.floor!=null
func _configure_world_view() -> void:
	if painting_ready():
		$MineBackdrop.z_index=-20
		$MineBackdrop.configure(layout.arena,"B08",layout_seed,layout_id)
		$MineBackdrop.configure_layout(layout)
		if OS.get_cmdline_user_args().has("--b08-native-room-detail"):
			$MineBackdrop.environment_chunks.configure_candidate_detail(true)
		$MineBackdrop.show()
		if is_instance_valid(camera): camera.configure(self,player,painted_mapping.floor.bounds,$MineBackdrop.painted_bounds())
	else:
		$MineBackdrop.hide()
		if is_instance_valid(camera): camera.configure(self,player,ARENA,ARENA)
func _refresh_terrain_canvas() -> void: pass
func _draw_interaction_focus(_canvas: Node2D) -> void: pass
func _update_encounters(_delta: float = 0.0) -> void: pass
func interaction_hint() -> String: return ""
func navigation_target() -> Dictionary: return {"position":exit_position,"kind":"preview","title":"Next candidate room"}

func _open_room(id: String) -> void:
	_release_candidate_ui()
	for actor: Node in enemies.get_children(): actor.free()
	for shot: Node in projectiles.get_children(): shot.free()
	if enemy_skills!=null: enemy_skills.reset_room()
	feathers.clear()
	warnings.clear()
	wind = preload("res://scripts/levels/b08/wind_state.gd").new()
	harbor.reset()
	if not load_room_layout(id):
		push_error("B08 room rejected: "+configuration_error)
		request_quit()
		return
	var ids: Array = []
	for lane: Dictionary in SkyGeometry.lanes(id): ids.append(lane.id)
	wind.configure(ids)
	player.position = layout.entry
	player.clear_movement_target()
	player.clear_buffered_skill()
	player.knockback = Vector2.ZERO
	_channel_lane = ""
	_authored_waves = preload("res://scripts/levels/b08/encounters.gd").waves(id,difficulty)
	_next_wave = 0
	_wave_delay = 3.0
	if not _authored_waves.is_empty(): _spawn_authored_wave()
	elif id=="BO08": spawn_enemy(SkyGeometry.point([1400,650]),"BO08",40)
	var flag_profile := SkyNumbers.profile("B08-M02",difficulty,"normal",int(SkyContent.room(id).level))
	flag_profile["enemy_id"] = "B08-FLAG"
	flag_profile["name"] = "报风旗"
	flag_profile["max_hp"] = int(round(float(flag_profile.max_hp)*.4))
	_flag = SkyActor.new()
	_flag.room = self
	_flag.configure(flag_profile,{"reward_enabled":false,"static_actor":true})
	_flag.position = clamp_actor(layout.entry+Vector2(120,-75),20)
	enemies.add_child(_flag)
	_configure_sky_environment()
	_configure_world_view()
	_configure_candidate_ui()
	_floor_canvas.queue_redraw()

func _release_candidate_ui() -> void:
	if is_instance_valid(candidate_ui):
		candidate_ui.close_panels()
		candidate_ui.free()
	candidate_ui=null
func _configure_candidate_ui() -> void:
	_hud.show()
	if not ExistingHUD.enabled_for(self): return
	var host:=ExistingHUD.new()
	host.room=self
	add_child(host)
	candidate_ui=host
	_hud.hide()

func _configure_sky_environment() -> void:
	if is_instance_valid(sky_interactions): sky_interactions.free()
	sky_interactions=null
	if is_instance_valid(sky_environment): sky_environment.free()
	sky_environment=null
	sky_projectile_art=null
	if layout_id!="L43" or not OS.get_cmdline_user_args().has("--b08-art-l43"): return
	var convergence:=OS.get_cmdline_user_args().has("--b08-art-convergence")
	if not painting_ready():
		var environment:=preload("res://scripts/levels/b08/presentation/l43_environment.gd").new()
		add_child(environment)
		if not environment.configure(layout_id,OS.get_cmdline_user_args().has("--b08-art-background-depth-review"),convergence):
			push_error("B08 reference art rejected: "+str(environment.errors)); environment.free(); return
		sky_environment=environment
	if convergence:
		var projectile_art:=preload("res://scripts/levels/b08/presentation/projectile_art.gd").new()
		if projectile_art.configure(layout_id): sky_projectile_art=projectile_art
		var interaction_art:=preload("res://scripts/levels/b08/presentation/interaction_art.gd").new()
		add_child(interaction_art)
		if interaction_art.configure(self,_flag): sky_interactions=interaction_art
		else: interaction_art.free()
func spawn_enemy(at: Vector2, id: String = "", _level: int = 1, options: Dictionary = {}) -> EnemyActor:
	if id not in SkyBrain.IMPLEMENTED or _living_combatants()>=6 or enemies.get_child_count()>=18: return null
	var p: Dictionary = options.get("profile",SkyNumbers.profile(id,difficulty))
	if p.is_empty(): return null
	var actor: EnemyActor = SkyActor.new()
	actor.room = self
	actor.configure(p,{"reward_enabled":false,"actor_kind":"boss" if id=="BO08" else "enemy"})
	actor.position = clamp_actor(at,actor.navigation_radius)
	enemies.add_child(actor)
	return actor
func spawn_escorts(owner: Node2D) -> void:
	for sign_value: int in [-1,1]:
		var p := SkyNumbers.profile("B08-M01",difficulty,"normal",40)
		p.max_hp = int(p.max_hp/2)
		var actor := spawn_enemy(owner.position+Vector2(sign_value*90,30),"B08-M01",40,{"profile":p})
		if actor!=null: actor.owner_enemy = weakref(owner)
func enemy_died(enemy: EnemyActor) -> void:
	harbor.actor_died(enemy)
	if enemy==_flag: wind.break_flag()
	release_warning(str(enemy.get_instance_id()))
	wind.release_dive(str(enemy.get_instance_id()))
	for actor: Node in enemies.get_children():
		if actor.owner_enemy!=null and actor.owner_enemy.get_ref()==enemy: actor.queue_free()
	if enemy_skills!=null: enemy_skills.cancel_owner(enemy)
	# Deliberately no Game.record_kill, XP, loot or completion transactions.

func _physics_process(delta: float) -> void:
	if not _started or shutdown_started or Game.run==null or get_tree().paused: return
	if _lifecycle_frames>0:
		_lifecycle_frames -= 1
		if _lifecycle_frames==0:
			request_quit()
			return
	if Game.run.hp<=0:
		_hud.text = "B08 debug candidate: defeated. Close preview; no progress saved."
		return
	elapsed += delta
	if release_gate and _all_inputs_released(): release_gate = false
	if not _channel_lane.is_empty():
		var lane: Dictionary = _lane(_channel_lane)
		if input_blocked or Game.run.hp<_channel_hp or player.position.distance_to(lane.vane)>68 or not has_line_of_sight(player.position,lane.vane):
			wind.cancel_turn()
			_channel_lane = ""
	var events: Array = wind.advance(delta)
	for event: Dictionary in events:
		if event.kind=="turn_warning": _channel_lane = ""
	if controls_enabled() and Input.is_action_just_pressed("interact"): interact()
	harbor.advance(delta)
	_tick_authored_waves(delta)
	_tick_feathers(delta)
	if is_instance_valid(sky_interactions): sky_interactions.sync(delta)
	for index in range(effects.size()-1,-1,-1):
		effects[index].remaining -= delta
		if effects[index].remaining<=0: effects.remove_at(index)
	_hud.text = "%s · %s · D%d · HP %d/%d\nB08 candidate / Lv20 diagnostic hero / partial art / no rewards\nM01–06 + BO08 combat slice. L45–48: topology only.\nRight-click move · QWER skills · F vane/exit · Esc quit\nVane: %.1fs channel + %.1fs warning | active threats %d/2" % [layout_id,SkyContent.room(layout_id).name,difficulty,Game.run.hp,Game.run.max_hp,float(wind.channel.get("remaining",0)),float(wind.pending.get("remaining",0)),warnings.size()]
	queue_redraw()
	_floor_canvas.queue_redraw()
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: request_quit()
func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and _started: request_quit()
func request_quit() -> void:
	if _quit_requested: return
	_quit_requested = true
	if not await cleanup_for_exit(): push_warning("B08 combat audio cleanup timed out")
	get_tree().quit(0 if shutdown_clean else 1)
func cleanup_for_exit() -> bool:
	if shutdown_started:
		if not shutdown_done: await shutdown_ready
		return shutdown_clean
	shutdown_started = true
	_release_candidate_ui()
	set_input_blocked(true)
	wind.cancel_turn()
	_channel_lane = ""
	# Block new actor/input sound requests while the existing AudioServer-backed
	# cleanup observes weak playback references. Audio keeps its ALWAYS process.
	process_mode = Node.PROCESS_MODE_DISABLED
	set_process_input(false)
	set_process_unhandled_input(false)
	shutdown_clean = true
	if is_instance_valid(combat_audio):
		combat_audio.stop_all()
		shutdown_clean = await combat_audio.wait_for_cleanup()
	shutdown_done = true
	shutdown_ready.emit()
	return shutdown_clean
func interact() -> void:
	if not controls_enabled(): return
	for lane: Dictionary in SkyGeometry.lanes(layout_id):
		if player.position.distance_to(lane.vane)<=68 and has_line_of_sight(player.position,lane.vane) and wind.begin_turn(lane.id,"player"):
			_channel_lane = lane.id
			_channel_hp = Game.run.hp
			return
	if player.position.distance_to(exit_position)<80:
		if not exit_ready(): return
		var ids := SkyContent.room_ids()
		var next := ids.find(layout_id)+1
		if next>=ids.size(): request_quit()
		else: _open_room(ids[next])
func exit_ready() -> bool:
	if _next_wave<_authored_waves.size(): return false
	for actor: EnemyActor in enemies.get_children():
		if actor.is_alive() and not actor.static_actor: return false
	return true

func lane_at(at: Vector2) -> Dictionary: return SkyGeometry.lane_at(layout_id,at)
func _lane(id: String) -> Dictionary:
	for lane: Dictionary in SkyGeometry.lanes(layout_id):
		if lane.id==id: return lane
	return {}
func wind_multiplier(at: Vector2, motion: Vector2) -> float:
	var lane := lane_at(at)
	return 1.0 if lane.is_empty() else wind.movement(lane.id,lane.direction,motion)
func admit_warning(owner: String) -> bool:
	if warnings.has(owner): return true
	if warnings.size()>=2: return false
	warnings[owner] = true
	return true
func release_warning(owner: String) -> void: warnings.erase(owner)
func on_screen(at: Vector2) -> bool:
	return get_viewport_rect().grow(-35).has_point(get_global_transform_with_canvas()*at)
func valid_ground(at: Vector2, radius: float = 0.0) -> bool:
	return painted_mapping.floor.contains(at,radius) if painting_ready() else SkyGeometry.contains(layout_id,at,radius)
func clamp_actor(at: Vector2, radius: float) -> Vector2:
	if painting_ready(): return painted_mapping.floor.clamp_point(at,radius)
	if valid_ground(at,radius): return at
	var closest := SkyGeometry.point(SkyGeometry.ENTRY.get(layout_id,[1400,900]))
	var distance := INF
	for shape: Rect2 in SkyGeometry.floors(layout_id):
		var inner := shape.grow(-radius-1)
		var candidate := Vector2(clampf(at.x,inner.position.x,inner.end.x),clampf(at.y,inner.position.y,inner.end.y))
		if candidate.distance_squared_to(at)<distance and valid_ground(candidate,radius): closest=candidate; distance=candidate.distance_squared_to(at)
	return closest
func move_actor(from: Vector2, displacement: Vector2, radius: float) -> Vector2:
	var motion := displacement
	if is_instance_valid(player) and from.is_equal_approx(player.position) and is_equal_approx(radius,Balance.PLAYER_RADIUS) and player.dash_remaining<=0 and player.knockback.length_squared()<.01 and not player.abilities.busy(): motion *= wind_multiplier(from,motion)
	return _move_ground(from,motion,radius)
func _move_ground(from: Vector2, motion: Vector2, radius: float) -> Vector2:
	return painted_mapping.floor.move(from,motion,radius) if painting_ready() else SkyGeometry.move(layout_id,from,motion,radius)
func blocked_fraction(from: Vector2, to: Vector2, radius: float = 0.0) -> float:
	if painting_ready(): return painted_mapping.floor.blocked_fraction(from,to,radius)
	var steps := maxi(1,ceili(from.distance_to(to)/4))
	for index in range(1,steps+1):
		if not valid_ground(from.lerp(to,float(index)/steps),radius): return float(index-1)/steps
	return 1.0
func has_line_of_sight(from: Vector2, to: Vector2) -> bool: return blocked_fraction(from,to)>=.999
func _build_navigation() -> void:
	_grid.region = Rect2i(0,0,42,28)
	_grid.cell_size = Vector2(40,40)
	_grid.offset = Vector2(20,20)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	for x in 42:
		for y in 28: _grid.set_point_solid(Vector2i(x,y),not valid_ground(Vector2(x*40+20,y*40+20),40))
func navigation_direction(from: Vector2, target: Vector2, radius: float = 0.0) -> Vector2:
	if blocked_fraction(from,target,radius)>.999: return from.direction_to(target)
	var start := Vector2i((from-Vector2(20,20))/40)
	var finish := Vector2i((clamp_actor(target,radius)-Vector2(20,20))/40)
	if not _grid.is_in_boundsv(start) or not _grid.is_in_boundsv(finish) or _grid.is_point_solid(start) or _grid.is_point_solid(finish): return Vector2.ZERO
	var path := _grid.get_point_path(start,finish)
	return from.direction_to(path[1]) if path.size()>1 else Vector2.ZERO

func packet(actor: Node2D, action: Dictionary, coefficient: float) -> Dictionary:
	shot_serial += 1
	var phase := 1
	if actor.enemy_id=="BO08": phase = 3 if actor.health.current/actor.health.maximum<=.35 else 2 if actor.health.current/actor.health.maximum<=.70 else 1
	var factor: float = [1.0,1.15,1.35,1.6,1.9][difficulty]*(1.0+.1*(phase-1)) if actor.enemy_id=="BO08" else 1.25*[1.0,1.12,1.28,1.48,1.72][difficulty]
	if bool(action.get("basic",false)): factor = 1.0
	var command := {"damage":int(round(float(actor.profile.damage)*coefficient*float(action.get("damage_factor",1))*factor)),"damage_type":"physical","enemy_id":actor.enemy_id,"damage_source":"b08_"+str(action.kind),"ruleset_version":2}
	return Crit.freeze(command,actor.profile,8008,str(actor.enemy_id)+":"+str(shot_serial))
func _hurt(actor: Node2D, data: Dictionary, push: float = 0) -> void:
	if Game.run==null or Game.run.hp<=0: return
	var before: float = Game.run.hp+Game.run.shield
	var previous_knockback: Vector2 = player.knockback
	player.receive_damage(float(data.damage),actor.position,data)
	if Game.run==null: return
	if Game.run.hp+Game.run.shield<before:
		wind.cancel_turn()
		_channel_lane = ""
		if wind.admit_displacement("player"):
			if push>0:
				player.knockback = Vector2.ZERO
				player.position = _move_ground(player.position,actor.position.direction_to(player.position)*push,Balance.PLAYER_RADIUS)
		else: player.knockback = previous_knockback
func hit_circle(actor: Node2D, action: Dictionary, coefficient: float, radius: float) -> void:
	if player.position.distance_to(action.target)<=radius+Balance.PLAYER_RADIUS and has_line_of_sight(action.target,player.position): _hurt(actor,packet(actor,action,coefficient))
func hit_line(actor: Node2D, action: Dictionary, coefficient: float, reach: float, width: float, push: float = 0) -> void:
	var origin: Vector2 = action.origin
	var end := origin+origin.direction_to(action.target)*reach
	var nearest := Geometry2D.get_closest_point_to_segment(player.position,origin,end)
	if nearest.distance_to(player.position)<=width*.5+Balance.PLAYER_RADIUS and has_line_of_sight(origin,player.position): _hurt(actor,packet(actor,action,coefficient),push)
func hit_fan(actor: Node2D, action: Dictionary, coefficient: float, reach: float, half_angle: float) -> void:
	var offset: Vector2 = player.position-action.origin
	var direction: Vector2 = Vector2(action.target-action.origin).normalized()
	if offset.length()<=reach+Balance.PLAYER_RADIUS and (offset.length()<Balance.PLAYER_RADIUS or absf(direction.angle_to(offset))<=deg_to_rad(half_angle)) and has_line_of_sight(action.origin,player.position): _hurt(actor,packet(actor,action,coefficient))
func fire_feather(actor: Node2D, action: Dictionary, coefficient: float, reach: float, angle: float = 0, group: Dictionary = {}) -> void:
	if feathers.size()>=48: return
	var shot: Dictionary={"position":actor.position,"direction":actor.position.direction_to(action.target).rotated(angle),"remaining":reach,"owner":weakref(actor),"packet":packet(actor,action,coefficient),"group":group}
	if sky_projectile_art!=null: sky_projectile_art.attach_launch(actor,shot)
	feathers.append(shot)
func fire_fan(actor: Node2D, action: Dictionary) -> void:
	var group := {"hits":0}
	for angle: int in [-40,-20,0,20,40]: fire_feather(actor,action,.35,420,deg_to_rad(angle),group)
func _tick_feathers(delta: float) -> void:
	for shot: Dictionary in feathers.duplicate():
		var owner: Node2D = shot.owner.get_ref()
		if not is_instance_valid(owner) or not owner.is_alive(): feathers.erase(shot); continue
		var origin: Vector2 = shot.position
		var distance := minf(float(shot.remaining),320*delta)
		var target: Vector2 = origin+shot.direction*distance
		var fraction := blocked_fraction(origin,target,3)
		target = origin.lerp(target,fraction)
		var near := Geometry2D.get_closest_point_to_segment(player.position,origin,target)
		if near.distance_to(player.position)<=Balance.PLAYER_RADIUS+5:
			if shot.group.is_empty() or int(shot.group.hits)<2:
				_hurt(owner,shot.packet)
				if not shot.group.is_empty(): shot.group.hits+=1
			feathers.erase(shot)
			continue
		shot.position = target
		shot.remaining -= distance
		if shot.remaining<=0 or fraction<.999: feathers.erase(shot)

func _draw_floor() -> void:
	if not painting_ready() and not is_instance_valid(sky_environment):
		_floor_canvas.draw_rect(ARENA,Color("83b3cc"))
		for shape: Rect2 in SkyGeometry.floors(layout_id):
			_floor_canvas.draw_rect(shape,Color("eee8d5"))
			_floor_canvas.draw_rect(shape,Color("9d9174"),false,3)
	for lane: Dictionary in SkyGeometry.lanes(layout_id):
		var direction: Vector2 = wind.direction(lane.id,lane.direction)
		if painting_ready() or is_instance_valid(sky_environment):
			preload("res://scripts/levels/b08/presentation/wind_lane.gd").draw_lane(_floor_canvas,lane,wind,wind.now,bool(Game.profile.settings.get("reduced_fx",false)))
		else:
			_floor_canvas.draw_rect(lane.rect,Color(.35,.75,.84,.35))
			var center: Vector2 = lane.rect.get_center()
			_floor_canvas.draw_line(center-direction*40,center+direction*40,Color("396b95"),4)
			_floor_canvas.draw_line(center+direction*40,center+direction*23+direction.orthogonal()*13,Color("396b95"),4)
			_floor_canvas.draw_line(center+direction*40,center+direction*23-direction.orthogonal()*13,Color("396b95"),4)
		if not is_instance_valid(sky_interactions):
			_floor_canvas.draw_circle(lane.vane,14,Color("d3a43a"))
			_floor_canvas.draw_line(lane.vane,lane.vane+direction*32,Color("305474"),4)
			if wind.pending.get("lane","")==lane.id: _floor_canvas.draw_arc(lane.vane,25,0,TAU,32,Color("ef714a"),3)
	if is_instance_valid(sky_interactions): sky_interactions.draw_floor(_floor_canvas)
	else: _floor_canvas.draw_circle(exit_position,27,Color("70aa92"))
func _draw() -> void:
	if not _started: return
	for actor: EnemyActor in enemies.get_children():
		if not actor.is_alive(): continue
		draw_circle(actor.position,actor.navigation_radius,Color(0.12,0.24,0.3,.35))
		if actor.brain==null or actor.brain.action.is_empty(): continue
		var brain = actor.brain
		var action: Dictionary = brain.action
		if brain.phase not in ["warning","transit","patrol_wait"]: continue
		var color := Color("ed7d44") if brain.phase=="warning" else Color("d44740")
		if action.kind in ["dive","patrol","flank","return","chime"]:
			var points: Array = action.get("points",[action.target])
			for point: Vector2 in points:
				draw_arc(point,float(action.radius),0,TAU,48,color,3)
				draw_line(point-Vector2(9,0),point+Vector2(9,0),color,2)
		elif action.kind=="support":
			draw_line(action.origin,action.target,Color("7cabc8"),2)
			draw_arc(action.target,24,0,TAU,24,Color("7cabc8"),2)
		elif action.kind=="shield":
			var facing: Vector2 = Vector2(action.target-action.origin).normalized()
			draw_line(action.origin,action.target,color,3)
			var far: Vector2 = action.target+facing*100
			var wing: Vector2 = facing.orthogonal()*32.5
			draw_polyline(PackedVector2Array([action.target-wing,far-wing,far+wing,action.target+wing]),color,3)
		else:
			var direction: Vector2 = action.origin.direction_to(action.target)
			var angles := [-40,-20,0,20,40] if action.kind=="fan" else [0]
			for angle: int in angles: draw_line(action.origin,action.origin+direction.rotated(deg_to_rad(angle))*320,color,3)
	harbor.draw_warnings(self)
	for shot: Dictionary in feathers:
		if sky_projectile_art!=null and sky_projectile_art.draw(self,shot): continue
		draw_line(shot.position-shot.direction*16,shot.position+shot.direction*6,Color("faf8d4"),4)

func _living_combatants() -> int:
	var count := 0
	for actor: EnemyActor in enemies.get_children():
		if actor.is_alive() and not actor.static_actor and not actor.is_queued_for_deletion(): count += 1
	return count
func _spawn_authored_wave() -> void:
	if _next_wave>=_authored_waves.size(): return
	for member: Dictionary in _authored_waves[_next_wave]:
		var p := SkyNumbers.profile(member.id,difficulty,member.rank,int(SkyContent.room(layout_id).level))
		spawn_enemy(SkyGeometry.point(member.at),member.id,int(p.enemy_level),{"profile":p})
	_next_wave += 1
	_wave_delay = 3.0
func _tick_authored_waves(delta: float) -> void:
	if _next_wave>=_authored_waves.size() or _living_combatants()>0: return
	_wave_delay -= delta
	if _wave_delay<=0: _spawn_authored_wave()
