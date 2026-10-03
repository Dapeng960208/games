extends RefCounted
## Executable candidate commands. Unimplemented species retain contact-only admission.
## Inputs are current B06 chapter and shared warning/numerical contracts, never art.
const Content = preload("res://scripts/levels/b06/world/content.gd")
const Numbers = preload("res://scripts/levels/b06/combat/enemy_numbers.gd")
const Timing = preload("res://scripts/domain/combat/enemy_warning_timing.gd")
const Props = preload("res://scripts/domain/combat/combat_properties.gd")
const IMPLEMENTED := [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18]
const CDS := [7,8,9,6,10,10,9,12,10,9,8,8,13,10,11,11,12,14]
const TELLS := [.9,1.1,.9,.8,1.0,.9,1.0,1.2,1.1,1.2,1.0,1.0,1.5,1.0,1.1,1.2,1.3,1.2]
const ACTIONS := ["trident_thrust","shell_bomb","shield_claw","needle_swim","bubble_shield","crab_mine","song_wave","coral_wall","siege_charge","pearl_pulse","lance_step","spiral_jet","bell_hasten","sawfin_leap","clam_volley","tidal_net","reef_ring","tidal_banner"]
const BOSS_ACTIONS := ["siege_claw","dual_cannon","tidal_wall","shell_bombard","coral_escort","return_pincer"]
const BOSS_GATES := [0,0,1,2,3,4]
const BOSS_CDS := [7,12,16,17,20,24]
const BOSS_TELLS := [1.2,1.3,1.5,1.4,1.2,1.6]
const BOSS_NAMES := ["破城钳","双口潮炮","潮线推进","壳上炮击","珊城护航","回潮夹击"]
static func implemented(id: String) -> bool:
	return id.begins_with("B06-M") and int(id.trim_prefix("B06-M")) in IMPLEMENTED
static func profile(id: String, level: int, difficulty: int, rank: String = "normal", calibration: Variant = null, version: int = 0) -> Dictionary:
	var result := Numbers.ordinary(id,level,difficulty,rank,calibration,version)
	if result.is_empty(): return {}
	var source := Content.enemy(id)
	result.merge({"name":source.name,"name_en":source.name_en,"role":source.profile,
		"archetype":{"F":"skirmisher","R":"skirmisher","C":"caster","S":"support","A":"assassin","T":"tank"}[source.profile],
		"behavior_id":"b06_"+ACTIONS[int(id.trim_prefix("B06-M"))-1],"navigation_radius":22.0 if source.profile=="T" else 18.0,
		"effective_threat_cost":1.0,"damage_type":"magic" if source.profile=="C" else "physical","damage_kind":"physical",
		"attack_parameters":{"range":result.attack_range,"summon_cap":0},"mechanics":[],"b06_combat_version":1,
		"b06_candidate_contact_only":not implemented(id),"gameplay_implemented":implemented(id)},true)
	return result
static func boss_profile(difficulty: int, calibration: Variant = null, version: int = 0) -> Dictionary:
	var result := Numbers.boss(difficulty,calibration,version)
	if result.is_empty(): return {}
	result.merge({"name":"行走巨蟹堡垒","name_en":"Walking Crab Fortress","clan":"sea","behavior_id":"boss_bo06",
		"navigation_radius":60.0,"attack_range":360.0,"recovery_seconds":1.4,"damage_type":"physical","phase_thresholds":[.7,.4],
		"immune_forced_movement":true,"effective_threat_cost":0.0,"reinforcement_cap":4,"reinforcement_budget":4,
		"reinforcement_waves":[],"reserved_summon_count":2,"reserved_summon_threat":2.0,
		"visual_asset":AssetCatalog.boss_body("BO06"),"b06_combat_version":1},true)
	return result
static func mechanics(actor: Node2D) -> Variant:
	return Props.read(Props.read(actor,"room"),"b06_mechanics")
static func wet(actor: Node2D) -> bool:
	var host: Variant = mechanics(actor)
	return host is Object and host.state.is_wet(host.patch_at(actor))
static func high(actor: Node2D) -> bool:
	var host: Variant = mechanics(actor)
	return host is Object and str(host.state.clock_state().phase)=="high"
static func base(p: Dictionary, origin: Vector2, target: Vector2) -> Dictionary:
	var direction := origin.direction_to(target)
	if direction.is_zero_approx(): direction=Vector2.RIGHT
	return {"b06_command":true,"caster_enemy_id":str(p.enemy_id),"ability_id":str(p.enemy_id)+":basic","ability_name":"潮击","ability_name_en":"Tidal Strike",
		"counter_cue":"离开锁定预警；收势时接近","counter_cue_en":"Leave the locked warning; approach during recovery","icon_id":str(p.enemy_id),
		"origin":origin,"target":target,"direction":direction,"kind":"melee","shape":"cone","range":90.0,"angle":1.8,"coefficient":100,
		"b06_phase":1,"stage":0,"stage_count":1,"damage_type":p.get("damage_type","physical"),"fx_color":Color("59c9de"),
		"difficulty":int(p.difficulty),"cooldown":0.0,"recovery":float(p.get("recovery_seconds",1.15)),"followups":[]}
static func basic(p: Dictionary, origin: Vector2, target: Vector2) -> Dictionary:
	return timed(base(p,origin,target),.8,int(p.difficulty))
static func active(p: Dictionary, origin: Vector2, target: Vector2, is_wet: bool, is_high: bool = false, cycle: int = 0) -> Dictionary:
	var id := str(p.enemy_id)
	if not implemented(id): return basic(p,origin,target)
	var n := int(id.trim_prefix("B06-M"))-1
	var d := int(p.difficulty)
	var c := base(p,origin,target)
	var source := Content.enemy(id)
	c.merge({"ability_id":id+":"+ACTIONS[n],"ability_name":source.name+" · "+ACTIONS[n],"ability_name_en":source.name_en+" · "+ACTIONS[n],
		"counter_cue":source.counter_and_drop_text,"active":true,"cooldown":float(CDS[n]),"range":float(p.attack_range),"wet":is_wet,"high":is_high,"cycle":cycle},true)
	var v: Vector2 = c.direction
	match n+1:
		1:
			c.merge({"shape":"line","width":36.0,"range":200.0 if d>=2 and is_wet else 150.0,"coefficient":110},true)
			if d>=2 and is_wet:
				c.merge({"kind":"charge","travel_distance":50.0,"duration":.2,"radius":18.0,"b06_thrust":true},true)
			if d>=4:
				var sweep := child(c,"melee","cone",40,.8)
				sweep.merge({"range":150.0,"angle":2.1,"direction":-v,"origin":origin+(v*50 if d>=2 and is_wet else Vector2.ZERO)},true)
				c.followups.append(sweep)
		2:
			c.merge({"kind":"ground_area","shape":"circle","radius":75.0,"coefficient":100,"lob":true},true)
			if d>=2:
				var foam := area(c,target,75,0,0)
				foam.merge({"duration":2.0,"tick_interval":.5,"status":{"id":"slow","magnitude":.8,"duration":.6},"continuous":true},true)
				c.followups.append(foam)
			if d>=4 and is_high: c.followups.append(area(c,target+v*95,75,40,.8))
		3:
			c.merge({"kind":"b06_shield_stance","range":100.0,"coefficient":0,"duration":2.5,"recovery":3.0,"reduction":.35},true)
			var claw := child(c,"melee","cone",100,2.5)
			claw.merge({"range":100.0,"angle":1.8},true)
			c.followups.append(claw)
		5:
			c.merge({"kind":"b06_shield","shape":"line","width":8.0,"range":240.0,"coefficient":0,"interruptible":true,"minimum_channel":1.0,"duration":5.0,"target_count":2 if d>=4 else 1,"shield_ratio":.05 if d>=4 else .08},true)
		6:
			c.merge({"kind":"b06_mine","shape":"circle","radius":70.0,"coefficient":0,"range":280.0,"mine_coefficient":100,"fuse":2.0,"count":2 if d>=2 else 1},true)
		4:
			c.merge({"kind":"charge","shape":"line","width":32.0,"radius":16.0,"range":220.0,"travel_distance":220.0,"duration":.45,"coefficient":85,"after_motion":"needle"},true)
		8:
			var center := origin+v*55
			var side := v.orthogonal()*60
			c.merge({"kind":"b06_wall","shape":"line","width":12.0,"range":200.0,"coefficient":0,"duration":7.0,"wall_start":center-side,"wall_end":center+side,"wall_center":center,"points":[center-side,center+side]},true)
		9:
			c.merge({"kind":"charge","shape":"line","width":52.0,"radius":26.0,"range":200.0,"travel_distance":200.0,"duration":.5,"coefficient":120,"after_motion":"siege","terminal_speed_multiplier":1.1 if d>=4 and is_high else 1.0},true)
		7:
			c.merge({"range":240.0,"angle":1.8,"coefficient":90,"b06_push":50.0},true)
			if d>=2:
				var echo := child(c,"melee","line",40,.8)
				echo.merge({"width":28.0,"range":240.0},true)
				echo.erase("b06_push")
				c.followups.append(echo)
		10:
			c.merge({"kind":"ground_area","shape":"circle","radius":95.0,"coefficient":90},true)
			if d>=2: c.followups.append(area(c,target,65,40,1.0 if d>=4 else .8))
		11:
			var side := v.orthogonal()*(80 if cycle%2==0 else -80)
			c.merge({"kind":"b06_hop","coefficient":0,"range":180.0,"displacement":side,"recovery":1.8},true)
			var lance := child(c,"melee","line",110,.8)
			lance.merge({"origin":origin+side,"direction":(origin+side).direction_to(target),"range":180.0,"width":32.0},true)
			c.followups.append(lance)
		12:
			c.merge({"shape":"line","range":320.0,"width":45.0,"coefficient":100},true)
			if d>=2:
				var jet := child(c,"ground_area","line",25,0)
				jet.merge({"duration":1.5,"tick_interval":1.0,"continuous":true},true)
				c.followups.append(jet)
			if d>=4:
				var recoil := child(c,"b06_reposition","circle",0,0)
				recoil.merge({"displacement":-v*60},true)
				c.followups.append(recoil)
		13:
			c.merge({"kind":"b06_hasten","shape":"line","width":8.0,"range":240.0,"coefficient":0,"interruptible":true,"target_count":2,"minimum_channel":1.5},true)
		14:
			c.merge({"kind":"charge","shape":"circle","radius":60.0,"coefficient":115,"range":150.0,"travel_distance":minf(150,origin.distance_to(target)),"target":origin+v*minf(150,origin.distance_to(target)),"duration":.35,"path_mode":"leap","landing_only":true,"landing_shape":"circle","after_motion":"sawfin","minimum_visible_seconds":1.0},true)
		15:
			c.merge({"kind":"b06_shell","range":280.0,"coefficient":0,"duration":2.0,"reduction":.4,"recovery":4.0},true)
			var volley := child(c,"projectile","line",45,2.0)
			volley.merge({"range":280.0,"width":14.0,"count":3,"projectile_angles":[-18.0,0.0,18.0],"speed":280.0,"radius":7.0,"max_target_hits":2,"b06_clam":true},true)
			c.followups.append(volley)
		16:
			c.merge({"kind":"b06_net","shape":"circle","radius":90.0,"coefficient":60,"range":280.0,"duration":3.0,"status":{"id":"root","duration":.6}},true)
		17:
			c.merge({"kind":"ground_area","shape":"ring","origin":origin,"target":origin,"radius":160.0,"inner_radius":80.0,"coefficient":120},true)
			if d>=2 and is_high:
				var reverse := area(c,origin,140,120,1.2)
				reverse.merge({"shape":"ring","inner_radius":110.0},true)
				c.followups.append(reverse)
		18:
			c.merge({"kind":"b06_banner","shape":"circle","radius":180.0,"range":200.0,"origin":origin,"target":origin,"coefficient":0,"duration":6.0},true)
	var result := timed(geometry(c),float(TELLS[n]),d)
	if c.has("minimum_channel"):
		result.tell=maxf(float(result.tell),float(c.minimum_channel)-float(result.lock))
		result.telegraph_seconds=result.tell
	if c.has("minimum_visible_seconds"):
		result.tell=maxf(float(result.tell),float(c.minimum_visible_seconds)-float(result.lock))
		result.telegraph_seconds=result.tell
	result.timing.tell_seconds=result.tell
	return result
static func child(source: Dictionary, kind: String, shape: String, coefficient: int, delay: float) -> Dictionary:
	var result := source.duplicate(true)
	for key in ["followups","after_motion","status","active","points","paths","delay","remaining","duration","travel_distance","lob","b06_thrust","terminal_speed_multiplier"]: result.erase(key)
	result.merge({"kind":kind,"shape":shape,"coefficient":coefficient,"delay":delay,"followups":[],"derived":true,"stage":int(source.get("stage",0))+1,"ability_id":str(source.ability_id)+":follow"},true)
	return result
static func area(source: Dictionary, at: Vector2, radius: float, coefficient: int, delay: float) -> Dictionary:
	var c := child(source,"ground_area","circle",coefficient,delay)
	c.merge({"origin":at,"target":at,"radius":radius,"duration":0.0},true)
	return c
static func timed(c: Dictionary, authored: float, difficulty: int, boss: bool = false) -> Dictionary:
	var timing := Timing.boss(authored,.4,difficulty,c,2) if boss else Timing.ordinary(authored,.4,difficulty,c,2)
	c.merge({"timing":timing,"telegraph_seconds":timing.tell_seconds,"locked_seconds":timing.lock_seconds,"tell":timing.tell_seconds,"lock":timing.lock_seconds},true)
	return c
static func geometry(c: Dictionary) -> Dictionary:
	if str(c.get("shape",""))=="line" and not c.has("points"):
		c.target=Vector2(c.origin)+Vector2(c.direction)*float(c.get("range",90))
		c.points=[c.origin,c.target]
	for i in range(c.get("followups",[]).size()): c.followups[i]=geometry(c.followups[i])
	return c
static func freeze_damage(c: Dictionary, p: Dictionary) -> Dictionary:
	var result := c.duplicate(true)
	preload("res://scripts/domain/combat/enemy_power_policy.gd").stamp(result, p)
	var damage := Numbers.skill_damage(p,int(c.get("coefficient",0)),int(c.get("b06_phase",1)),result)
	if damage<0: return {}
	result.merge({"damage":damage,"ruleset_version":2,"scale_version":10,"enemy_command_version":2},true)
	return result
static func boss_action(p: Dictionary, action: String, origin: Vector2, target: Vector2, phase: int, stage: int = 0) -> Dictionary:
	var i := BOSS_ACTIONS.find(action)
	if i<0 or int(p.difficulty)<BOSS_GATES[i]: return {}
	var c := base(p,origin,target)
	c.merge({"boss_id":"BO06","action_id":action,"ability_id":"BO06:"+action,"ability_name":BOSS_NAMES[i],"ability_name_en":action.replace("_"," "),
		"b06_phase":phase,"stage":stage,"cooldown":float(BOSS_CDS[i]),"recovery":1.4,"active":true,"range":520.0},true)
	var v: Vector2 = c.direction
	match action:
		"siege_claw": c.merge({"range":170.0,"angle":deg_to_rad(120),"coefficient":115},true)
		"dual_cannon":
			var side := -1 if stage==0 else 1
			if phase==3: side=-side
			c.merge({"shape":"line","origin":origin+v.orthogonal()*100*side,"width":60.0,"coefficient":80,"stage_count":2,"stage_interval":.8},true)
		"tidal_wall": c.merge({"shape":"line","width":100.0,"range":420.0,"coefficient":70,"b06_push":50.0},true)
		"shell_bombard": c.merge({"kind":"ground_area","shape":"circle","radius":90.0,"coefficient":85,"stage_count":2,"stage_interval":.8},true)
		"coral_escort": c.merge({"kind":"b06_summon","shape":"circle","radius":40.0,"coefficient":0,"count":2,"max_alive":2},true)
		"return_pincer":
			c.merge({"kind":"ground_area","shape":"ring" if stage==0 else "circle","origin":origin,"target":origin,"radius":300.0 if stage==0 else 140.0,"inner_radius":160.0 if stage==0 else 0.0,"coefficient":70 if stage==0 else 90,"stage_count":2,"stage_interval":1.2},true)
	return timed(geometry(c),float(BOSS_TELLS[i]),int(p.difficulty),true)
