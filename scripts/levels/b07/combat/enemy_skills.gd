extends RefCounted
## First playable B07 combat slice. Ten active kits and two boss abilities
## remain deferred; their authored catalog entries are not completion claims.
const Content = preload("res://scripts/levels/b07/world/content.gd")
const Numbers = preload("res://scripts/levels/b07/combat/enemy_numbers.gd")
const Timing = preload("res://scripts/domain/combat/enemy_warning_timing.gd")
const Props = preload("res://scripts/domain/combat/combat_properties.gd")
const IMPLEMENTED := [1,2,3,4,5,6,7,13]
const Support = preload("res://scripts/levels/b07/combat/support.gd")
const Presentation = preload("res://scripts/levels/b07/art/skill_presentation.gd")
const CDS := [7,8,7,10,11,9,10,7,9,13,11,9,11,8,12,10,12,14]
const TELLS := [.9,1.0,.9,1.0,1.3,1.1,1.2,.9,1.0,1.2,1.2,1.1,1.3,1.0,1.1,1.2,1.3,1.3]
const ACTIONS := ["sun_spear","camouflage_leap","returning_disc","sunscale_shield","turquoise_heal","sand_emerge","sand_vortex","mirror_slash","dart_venom","mirror_attendant","sand_ridge","awning_bolt","sun_beam","twin_slash","camouflage_banner","stargazer_arc","obelisk_cross","light_ceremony"]
const NAMES := ["锁线刺","沙纹跃击","沙盘回掷","日鳞光盾","绿松石祈愈","沙蜥钻出","驭沙漩涡","镜鳞斜斩","梭尾毒箭","搬镜仪式","石脊沙岭","幕棚重弩","日盘光束","裂沙双斩","迷彩沙旗","炽瞳扫光","方尖碑十字","驭光典仪"]
const BOSS_ACTIONS := ["sun_spear","golden_tail","sun_disc","altar_lines"]
const BOSS_GATES := [0,0,1,2]
const BOSS_CDS := [7,10,14,18]
const BOSS_TELLS := [1.2,1.2,1.3,1.5]
const BOSS_NAMES := ["日矛突贯","金尾横扫","日盘回旋","祭坛光网"]

static func implemented(id: String) -> bool:
	return id.begins_with("B07-M") and int(id.trim_prefix("B07-M")) in IMPLEMENTED

static func profile(id: String, level: int, difficulty: int, rank: String = "normal", calibration: Variant = null, version: int = 0) -> Dictionary:
	var result := Numbers.ordinary(id,level,difficulty,rank,calibration,version)
	if result.is_empty(): return {}
	var source := Content.enemy(id)
	var n := int(id.trim_prefix("B07-M"))-1
	result.merge({"name":source.name,"name_en":source.name_en,"role":source.profile,
		"archetype":{"F":"skirmisher","R":"skirmisher","C":"caster","S":"support","A":"assassin","T":"tank"}[source.profile],
		"behavior_id":"b07_"+ACTIONS[n] if implemented(id) else "b07_fallback_basic","navigation_radius":22.0 if source.profile=="T" else 18.0,
		"effective_threat_cost":1.0,"damage_type":"magic" if source.profile=="C" else "physical","damage_kind":"physical",
		"attack_parameters":{"range":result.attack_range,"summon_cap":0},"mechanics":[],"b07_combat_version":1,
		"b07_candidate_contact_only":not implemented(id),"gameplay_implemented":implemented(id),
		"implementation_status":"first_playable" if implemented(id) else "fallback_basic_active_deferred"},true)
	return result

static func boss_profile(difficulty: int, calibration: Variant = null, version: int = 0) -> Dictionary:
	var result := Numbers.boss(difficulty,calibration,version)
	if result.is_empty(): return {}
	result.merge({"name":"日轮蜥王","name_en":"Sunwheel Lizard King","clan":"lizard","behavior_id":"boss_bo07",
		"navigation_radius":48.0,"attack_range":240.0,"recovery_seconds":1.3,"damage_type":"physical","phase_thresholds":[.7,.35],
		"immune_forced_movement":true,"effective_threat_cost":0.0,"reinforcement_cap":0,"reinforcement_budget":0,
		"reinforcement_waves":[],"reserved_summon_count":0,"reserved_summon_threat":0.0,
		"b07_combat_version":1,"implementation_status":"first_playable","deferred_actions":["shadow_guards","sunwheel_return"]},true)
	return result

static func mechanics(actor: Node2D) -> Variant:
	return Props.read(Props.read(actor,"room"),"b07_mechanics")

static func lit(actor: Node2D) -> bool:
	var mechanism: Variant = mechanics(actor)
	return mechanism is Object and mechanism.has_method("is_lit") and bool(mechanism.is_lit(actor))

static func base(p: Dictionary, origin: Vector2, target: Vector2) -> Dictionary:
	var direction := origin.direction_to(target)
	if direction.is_zero_approx(): direction=Vector2.RIGHT
	return {"b07_command":true,"caster_enemy_id":str(p.enemy_id),"ability_id":str(p.enemy_id)+":basic","ability_name":"沙鳞近击","ability_name_en":"Sandscale Strike",
		"counter_cue":"离开锁定范围；从侧后方接近","counter_cue_en":"Leave the locked shape; approach from the flank","icon_id":str(p.enemy_id),
		"origin":origin,"target":target,"direction":direction,"kind":"melee","shape":"cone","range":90.0,"angle":1.8,"coefficient":100,
		"b07_phase":1,"stage":0,"stage_count":1,"damage_type":p.get("damage_type","physical"),"fx_color":Color("e66d45"),
		"difficulty":int(p.difficulty),"cooldown":0.0,"recovery":float(p.get("recovery_seconds",1.15)),"followups":[]}

static func basic(p: Dictionary, origin: Vector2, target: Vector2) -> Dictionary:
	return timed(base(p,origin,target),.8,int(p.difficulty))

static func active(p: Dictionary, origin: Vector2, target: Vector2, is_lit: bool, cycle: int = 0) -> Dictionary:
	var id := str(p.enemy_id)
	if not implemented(id): return basic(p,origin,target)
	var n := int(id.trim_prefix("B07-M"))-1
	var d := int(p.difficulty)
	var c := base(p,origin,target)
	c.merge({"ability_id":id+":"+ACTIONS[n],"ability_name":NAMES[n],"ability_name_en":ACTIONS[n].replace("_"," "),
		"active":true,"cooldown":float(CDS[n]),
		"range":float(p.attack_range),"lit":is_lit,"cycle":cycle},true)
	var v: Vector2 = c.direction
	# Live cues describe the command being built, not the cross-tier drop catalog.
	match n+1:
		1:
			c.merge({"shape":"line","width":30.0,"range":180.0,"coefficient":110,
				"counter_cue":"侧走离开矛线","counter_cue_en":"Step sideways out of the spear line"},true)
			if d>=2:
				var tail := child(c,"melee","cone",40,.8)
				tail.merge({"range":110.0,"angle":PI,"direction":-v,"body_bound":true,"minimum_visible_seconds":.8,
					"counter_cue":"避开身后尾扫的独立预警","counter_cue_en":"Avoid the separately warned rear tail sweep"},true)
				c.followups.append(tail)
				c.counter_cue+="；避开身后尾扫的独立预警"
				c.counter_cue_en+="; avoid the separately warned rear tail sweep"
			if d>=4 and is_lit:
				var step := child(c,"b07_reposition","circle",0,1.2)
				step.merge({"displacement":v*60,"harmless":true},true)
				c.followups.append(step)
		2:
			var distance := minf(210,origin.distance_to(target))
			c.merge({"kind":"charge","shape":"circle","radius":55.0,"coefficient":95,"range":210.0,"travel_distance":distance,
				"target":origin+v*distance,"duration":.4,"path_mode":"leap","arc_height":0.0,"landing_only":true,"landing_shape":"circle",
				"minimum_visible_seconds":1.0,"b07_after_motion":"sand_ball","recovery":1.2,
				"counter_cue":"离开跃击落点；光照、近身或造成伤害可显形","counter_cue_en":"Leave the landing zone; light, proximity or damage reveals camouflage"},true)
		3:
			c.merge({"kind":"projectile","shape":"line","range":260.0,"width":22.0,"radius":11.0,"speed":320.0,"pierce":true,"coefficient":100,
				"counter_cue":"侧走避开去程飞盘","counter_cue_en":"Step sideways out of the outbound disc path"},true)
			if d>=2: c["disc_return"]={"coefficient":40,"diagonal":d>=4 and is_lit,"sign":1 if cycle%2==0 else -1,"gap":.8}
		4:
			c.merge({"kind":"b07_shield","coefficient":0,"range":110.0,"duration":2.0,"recovery":1.2,"body_bound":true,
				"counter_cue":"绕到盾后，避开盾击","counter_cue_en":"Move behind the shield and avoid the shield bash"},true)
			var bash := child(c,"melee","cone",110,2.0)
			bash.merge({"range":110.0,"angle":1.9,"body_bound":true,"b07_push":50.0 if d>=2 else 0.0,"shield_bash":true},true)
			c.followups.append(bash)
		5:
			# Unspecified range/duration use explicit candidate-local defaults.
			c.merge({"kind":"b07_heal","shape":"line","range":200.0,"width":10.0,"coefficient":0,
				"target_count":2 if d>=4 else 1,"heal_ratio":.03 if d>=4 else .04 if d>=2 else .06,
				"shield_ratio":.04 if d>=2 else 0.0,"shield_duration":3.0,"interruptible":true,
				"minimum_visible_seconds":1.3,"fx_color":Color("66d3b0"),
				"counter_cue":"移开照向目标的光束，或打断祀者","counter_cue_en":"Move the light off the heal target or interrupt the caster"},true)
		6:
			var distance := minf(150,origin.distance_to(target))
			c.merge({"kind":"charge","shape":"circle","radius":70.0,"coefficient":100,"range":150.0,
				"travel_distance":distance,"target":origin+v*distance,"duration":.3,"path_mode":"burrow","arc_height":0.0,
				"landing_only":true,"landing_shape":"circle","minimum_visible_seconds":1.1,"b07_after_motion":"sand_emerge",
				"b07_mound":true,"recovery":1.9 if d>=4 else 1.2,"recovery_floor":1.5 if d>=4 else 1.2,
				"counter_cue":"离开沙丘隆起的落点；出土后趁空窗反击","counter_cue_en":"Leave the mound landing zone; counterattack during emergence recovery"},true)
		7:
			c.merge({"kind":"b07_vortex","shape":"circle","radius":100.0,"coefficient":60,"range":280.0,"b07_pull":40.0,
				"counter_cue":"从侧面离开漩涡预警","counter_cue_en":"Move sideways out of the vortex warning"},true)
			if d>=2:
				var sand := area(c,target,100,20,0)
				sand.merge({"duration":2.0,"tick_interval":1.0,"continuous":true,"persistent_clearance":true},true)
				c.followups.append(sand)
			if d>=4:
				var line := child(c,"melee","line",30,2.8)
				line.merge({"origin":target,"target":target+v*180,"range":180.0,"width":26.0,"minimum_visible_seconds":.8},true)
				c.followups.append(line)
		13:
			c.merge({"shape":"line","range":360.0,"width":24.0,"coefficient":125,"damage_type":"magic","mirror_bend_requested":d>=2,
				"counter_cue":"侧走离开日盘光束","counter_cue_en":"Step sideways out of the sun beam"},true)
	var result := timed(geometry(c),float(TELLS[n]),d)
	return minimum_warning(result,float(c.get("minimum_visible_seconds",0)))

static func child(source: Dictionary, kind: String, shape: String, coefficient: int, delay: float) -> Dictionary:
	var result := source.duplicate(true)
	for key in ["followups","active","points","paths","delay","remaining","duration","travel_distance","disc_return","b07_after_motion","mirror_bend_requested","b07_push","b07_pull","body_bound"]: result.erase(key)
	result.merge({"kind":kind,"shape":shape,"coefficient":coefficient,"delay":delay,"followups":[],"derived":true,
		"stage":int(source.get("stage",0))+1,"ability_id":str(source.ability_id)+":follow"},true)
	return result

static func area(source: Dictionary, at: Vector2, radius: float, coefficient: int, delay: float) -> Dictionary:
	var c := child(source,"ground_area","circle",coefficient,delay)
	c.merge({"origin":at,"target":at,"radius":radius,"duration":0.0},true)
	return c

static func timed(c: Dictionary, authored: float, difficulty: int, boss: bool = false) -> Dictionary:
	var timing := Timing.boss(authored,.4,difficulty,c,2) if boss else Timing.ordinary(authored,.4,difficulty,c,2)
	c.merge({"timing":timing,"telegraph_seconds":timing.tell_seconds,"locked_seconds":timing.lock_seconds,"tell":timing.tell_seconds,"lock":timing.lock_seconds},true)
	return c

static func minimum_warning(c: Dictionary, seconds: float) -> Dictionary:
	c.tell=maxf(float(c.tell),seconds-float(c.lock))
	c.telegraph_seconds=c.tell
	c.timing.tell_seconds=c.tell
	return c

static func geometry(c: Dictionary) -> Dictionary:
	if str(c.get("shape",""))=="line" and not c.has("points"):
		c.target=Vector2(c.origin)+Vector2(c.direction)*float(c.get("range",90))
		c.points=[c.origin,c.target]
	for i in range(c.get("followups",[]).size()): c.followups[i]=geometry(c.followups[i])
	return c

## Freeze environmental paths during the tell. Returning projectiles never
## start on the far side of an obstacle, and no continuation re-aims on release.
static func constrain(actor: Node2D, source: Dictionary) -> Dictionary:
	var c := source.duplicate(true)
	var room: Variant = Props.read(actor,"room")
	var mechanism: Variant = mechanics(actor)
	if str(c.get("kind",""))=="b07_heal": return Support.link(actor,c)
	if str(c.get("kind",""))=="projectile" and room is Object and room.has_method("blocked_fraction"):
		var start: Vector2=c.origin
		var endpoint: Vector2=c.target
		var fraction: float=room.blocked_fraction(start,endpoint,float(c.get("radius",10)))
		c.target=start.lerp(endpoint,clampf(fraction,0,1))
		c.range=start.distance_to(c.target)
		c.points=[start,c.target]
	if c.has("disc_return"):
		var spec: Dictionary=c.disc_return
		var endpoint: Vector2=c.target
		var destination: Vector2=c.origin
		if bool(spec.diagonal): destination+=Vector2(c.direction).orthogonal()*80*int(spec.sign)
		var back := child(c,"projectile","line",int(spec.coefficient),float(c.range)/float(c.speed)+float(spec.gap))
		back.merge({"origin":endpoint,"target":destination,"direction":endpoint.direction_to(destination),"range":endpoint.distance_to(destination),
			"points":[endpoint,destination],"minimum_visible_seconds":float(spec.gap),"stage":1},true)
		if str(c.caster_enemy_id)=="B07-M03":
			back.merge({"counter_cue":"避开返程飞盘的独立预警","counter_cue_en":"Avoid the separately warned return disc path"},true)
			c.counter_cue="侧走避开去程飞盘；留意返程的独立预警"
			c.counter_cue_en="Step sideways out of the outbound disc path; watch the separately warned return path"
		c.followups.append(back)
	if bool(c.get("mirror_bend_requested",false)) and mechanism is Object and mechanism.has_method("enemy_attack_lines"):
		var lines: Array=mechanism.enemy_attack_lines(actor,1)
		if not lines.is_empty():
			var mirror: Dictionary=lines[0]
			var start: Vector2=mirror.origin
			var end: Vector2=mirror.target
			var bend := child(c,"melee","line",40,1.0 if int(c.difficulty)>=4 else .8)
			bend.merge({"origin":start,"target":end,"direction":start.direction_to(end),"range":start.distance_to(end),"points":[start,end],
				"mirror_id":mirror.mirror_id,"mirror_state":mirror.mirror_state,"minimum_visible_seconds":1.0 if int(c.difficulty)>=4 else .8,
				"counter_cue":"避开折射光线；转镜可取消该段","counter_cue_en":"Avoid the reflected beam; turn its mirror to cancel it"},true)
			c.followups.append(bend)
			c.counter_cue="侧走离开日盘光束；留意折射段，转镜可取消该段"
			c.counter_cue_en="Step sideways out of the sun beam; watch the reflected beam and turn its mirror to cancel it"
	for i in range(c.followups.size()):
		var follow: Dictionary=c.followups[i]
		if bool(follow.get("persistent_clearance",false)):
			follow["admission_deferred"]=not (mechanism is Object and mechanism.has_method("admit_persistent_area") and bool(mechanism.admit_persistent_area(follow.target,float(follow.radius))))
	return c

static func freeze_damage(c: Dictionary, p: Dictionary) -> Dictionary:
	var result := c.duplicate(true)
	preload("res://scripts/domain/combat/enemy_power_policy.gd").stamp(result,p)
	var damage := Numbers.skill_damage(p,int(c.get("coefficient",0)),int(c.get("b07_phase",1)),result)
	if damage<0: return {}
	result.merge({"damage":damage,"ruleset_version":2,"scale_version":10,"enemy_command_version":2},true)
	return result

static func boss_action(p: Dictionary, action: String, origin: Vector2, target: Vector2, phase: int) -> Dictionary:
	var i := BOSS_ACTIONS.find(action)
	if i<0 or int(p.difficulty)<BOSS_GATES[i]: return {}
	var c := base(p,origin,target)
	c.merge({"boss_id":"BO07","action_id":action,"ability_id":"BO07:"+action,"ability_name":BOSS_NAMES[i],"ability_name_en":action.replace("_"," "),
		"b07_phase":phase,"cooldown":float(BOSS_CDS[i]),"recovery":1.3,"active":true},true)
	var v: Vector2=c.direction
	match action:
		"sun_spear": c.merge({"shape":"line","width":38.0,"range":240.0,"coefficient":120},true)
		"golden_tail": c.merge({"shape":"ring","target":origin,"radius":170.0,"inner_radius":38.0,"ring_start":v.angle()+PI*.5,"ring_end":v.angle()+PI*1.5,"coefficient":100},true)
		"sun_disc": c.merge({"kind":"projectile","shape":"line","range":360.0,"width":28.0,"radius":14.0,"speed":360.0,"pierce":true,"coefficient":80,
			"disc_return":{"coefficient":50,"diagonal":false,"sign":1,"gap":1.0},"recovery":2.4},true)
		"altar_lines": c.merge({"kind":"b07_altar_lines","shape":"line","range":0.0,"width":24.0,"coefficient":80,"damage_type":"magic","mirror_lines":[],"recovery":1.5},true)
	return timed(geometry(c),float(BOSS_TELLS[i]),int(p.difficulty),true)
