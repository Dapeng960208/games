extends RefCounted
## B05 executable authority. Distances are world pixels; coefficients are integer
## hundredths. Authored warning inputs go through the existing shared helper once.
const Content = preload("res://scripts/levels/b05/world/content.gd")
const Numbers = preload("res://scripts/levels/b05/combat/enemy_numbers.gd")
const Timing = preload("res://scripts/domain/combat/enemy_warning_timing.gd")
const Properties = preload("res://scripts/domain/combat/combat_properties.gd")
const CDS := [6,7,6,10,10,7,9,12,7,8,10,8,8,11,9,8,11,14]
const TELLS := [.9,1.0,.8,1.2,1.1,.8,1.1,1.0,.9,.9,1.0,1.0,1.0,1.5,1.1,1.0,1.2,1.2]
const ACTIONS := ["vine_sweep","seed_lob","moss_slide","dew_channel","briar_fence","leaf_lunge","bloom_bind","root_share","thorn_roll","pollen_spray","resin_guard","flytrap_lob","graft_slam","sun_beam","bridge_vine","capsule_fan","ancient_slam","season_mode"]
const BOSS_ACTIONS := ["crown_sweep","three_roots","pod_rain","growth_rings","bloom_transplant","season_bloom"]
const BOSS_GATES := [0,0,1,2,3,4]
const BOSS_PHASES := [1,1,2,1,2,3]
const BOSS_CDS := [7,12,14,18,20,24]
const BOSS_TELLS := [1.2,1.3,1.4,1.5,1.2,1.6]
const BOSS_NAMES := ["千枝横扫","蔓根三线","花荚雨","生长环","护蕊移栽","四季盛放"]
const BOSS_NAMES_EN := ["Crown Sweep","Three Root Lines","Seedpod Rain","Growth Rings","Bloom Transplant","Four Seasons Bloom"]

static func profile(id: String, level: int, difficulty: int, rank: String = "normal", calibration: Variant = null, version: int = 0) -> Dictionary:
	var result := Numbers.ordinary(id,level,difficulty,rank,calibration,version)
	if result.is_empty(): return {}
	var source := Content.enemy(id)
	result.merge({"name":source.name,"name_en":source.name_en,"role":source.profile,
		"archetype":{"F":"skirmisher","R":"skirmisher","C":"caster","S":"support","A":"assassin","T":"tank"}[source.profile],
		"behavior_id":"b05_"+ACTIONS[index(id)],"navigation_radius":22.0 if source.profile == "T" else 18.0,
		"effective_threat_cost":2.0 if source.profile in ["S","T"] else 1.0,
		"damage_type":"magic" if source.profile == "C" else "physical","damage_kind":"physical",
		"attack_parameters":{"range":float(result.attack_range),"summon_cap":0},"difficulty_mechanics":{"difficulty":difficulty},"mechanics":[],"b05_combat_version":1,"gameplay_implemented":true,"skills":Content.skills_for_difficulty(id,difficulty)},true)
	return result

static func boss_profile(difficulty: int, calibration: Variant = null, version: int = 0) -> Dictionary:
	var result := Numbers.boss(difficulty,calibration,version)
	if result.is_empty(): return {}
	result.merge({"name":"千枝花冠树王","name_en":"Thousand-Branch Crown King","clan":"plant",
		"behavior_id":"boss_bo05","navigation_radius":60.0,"attack_range":360.0,"damage_type":"physical",
		"phase_thresholds":[.7,.35],"immune_forced_movement":true,"effective_threat_cost":0.0,
		"reinforcement_cap":4,"reinforcement_budget":4,"reinforcement_waves":[],"reserved_summon_count":2,
		"reserved_summon_threat":2.0,"visual_asset":AssetCatalog.boss_body("BO05"),"b05_combat_version":1},true)
	return result

static func index(id: String) -> int:
	return int(id.trim_prefix("B05-M"))-1

static func connected(actor: Node2D) -> bool:
	var mechanism: Variant = mechanics(actor)
	return mechanism is Object and mechanism.has_method("connected") and bool(mechanism.connected(actor))

static func mechanics(actor: Node2D) -> Variant:
	return Properties.read(Properties.read(actor,"room"),"b05_mechanics")

static func base(profile_value: Dictionary, origin: Vector2, target: Vector2) -> Dictionary:
	var id: String = str(profile_value.enemy_id)
	var direction := origin.direction_to(target)
	if direction.is_zero_approx(): direction = Vector2.RIGHT
	return {"b05_command":true,"caster_enemy_id":id,"behavior_id":str(profile_value.get("behavior_id","")),
		"ability_id":id+":basic","ability_name":"枝击","ability_name_en":"Branch Strike",
		"counter_cue":"离开锁定范围；收势接近","counter_cue_en":"Leave the locked shape; approach during recovery",
		"icon_id":id,"origin":origin,"target":target,"direction":direction,"kind":"melee","shape":"cone",
		"range":90.0,"angle":1.8,"coefficient":100,"b05_phase":1,"stage":0,"stage_count":1,
		"damage_type":profile_value.get("damage_type","physical"),"fx_color":Color("df8c8c"),"cooldown":0.0,
		"recovery":float(profile_value.get("recovery_seconds",1.15)),"followups":[]}

static func basic(profile_value: Dictionary, origin: Vector2, target: Vector2) -> Dictionary:
	var command := base(profile_value,origin,target)
	return timed(command,.8,int(profile_value.difficulty))

static func active(profile_value: Dictionary, origin: Vector2, target: Vector2, on_network: bool, cycle: int = 0) -> Dictionary:
	var id := str(profile_value.enemy_id)
	var number := index(id)
	if number < 0 or number >= 18: return {}
	var d := int(profile_value.difficulty)
	var c := base(profile_value,origin,target)
	var source := Content.enemy(id)
	c.merge({"ability_id":id+":"+ACTIONS[number],"ability_name":str(source.name)+" · "+str(source.skills["0"].source_text),
		"ability_name_en":source.name_en+" · "+ACTIONS[number].replace("_"," "),"counter_cue":source.counter_and_drop_text,
		"cooldown":float(CDS[number]),"active":true,"on_network":on_network,"difficulty":d,"range":float(profile_value.attack_range)},true)
	var direction: Vector2 = c.direction
	match number+1:
		1:
			c.merge({"range":120.0,"angle":2.1,"coefficient":110},true)
			if d >= 2 and on_network:
				var line := child(c,"ground_area","line",0,.2)
				line.merge({"range":120.0,"width":30.0,"duration":2.0,"root_required":true,"status":{"id":"root","duration":.6,"protection_seconds":2.0},"tick_interval":1.0},true)
				c.followups.append(line)
				if d >= 4: c.followups.append(area(c,origin+direction*120,38,40,2.0,true))
		2:
			c.merge({"kind":"ground_area","shape":"circle","radius":65.0,"coefficient":100,"lob":true},true)
			if d >= 2:
				for sign_value in [-1,1]: c.followups.append(area(c,target+direction.orthogonal()*80*sign_value,30,30,.45))
			if d >= 4: c.followups.append(slow_area(c,target,65,2.0,0.0))
		3:
			c.merge({"kind":"charge","shape":"line","range":180.0,"travel_distance":180.0,"width":36.0,"radius":28.0,"coefficient":80,"landing_only":true,"landing_shape":"circle","target":origin+direction*180,"duration":.4,"after_motion":"moss"},true)
		4:
			c.merge({"kind":"b05_heal","shape":"line","width":8.0,"coefficient":0,"range":240.0,"interruptible":true,"heal_ratio":.06,"lifetime_heal_cap":.25,"target_count":1},true)
		5:
			c.merge({"kind":"ground_area","shape":"line","coefficient":50,"duration":6.0,"tick_interval":1.0,"breakable":true,"anchor_health":float(profile_value.max_hp)*.15,"width":24.0,"range":190.0 if d>=2 else 110.0,"b05_briar_haste":d>=4},true)
			var side := direction.orthogonal()
			c.origin = origin+direction*55-side*float(c.range)*.5
			c.direction = side
			c.target = c.origin+side*float(c.range)
			c.points = [c.origin,c.target]
		6:
			c.merge({"kind":"charge","shape":"line","width":28.0,"range":140.0,"travel_distance":140.0,"radius":18.0,"coefficient":100,"target":origin+direction*140,"duration":.32,"after_motion":"leaf"},true)
		7:
			c.merge({"kind":"ground_area","shape":"circle","radius":95.0,"coefficient":100,"status":{"id":"root","duration":.6,"protection_seconds":2.0}},true)
			if d>=2: c.followups.append(area(c,target+direction.orthogonal()*135,38,40,.8 if d>=4 else .45))
		8:
			c.merge({"kind":"b05_share","shape":"line","width":8.0,"range":260.0,"duration":5.0,"coefficient":0,"interruptible":true,"target_count":2},true)
		9:
			c.merge({"kind":"charge","shape":"line","width":44.0,"radius":24.0,"range":220.0,"travel_distance":220.0,"target":origin+direction*220,"duration":.5,"coefficient":90,"after_motion":"roll"},true)
		10:
			c.merge({"shape":"line","range":180.0,"width":70.0,"coefficient":70,"status":{"id":"slow","magnitude":.85,"duration":3.0}},true)
			if d>=2:
				var pollen := child(c,"ground_area","line",0,0)
				pollen.merge({"duration":2.0,"tick_interval":.5,"status":{"id":"slow","magnitude":.85,"duration":3.0}},true)
				c.followups.append(pollen)
			if d>=4: c.followups.append(child(c,"b05_reposition","circle",0,.3))
		11:
			c.merge({"kind":"b05_resin","shape":"cone","range":110.0,"angle":deg_to_rad(120),"coefficient":0,"duration":3.0,"shield_hp":float(profile_value.max_hp)*.2},true)
			var shove := child(c,"melee","cone",110,3.0)
			shove.erase("duration")
			shove["b05_resin_shove"] = true
			c.followups.append(shove)
		12:
			c.merge({"kind":"ground_area","shape":"circle","radius":70.0,"coefficient":90,"b05_pull":40.0},true)
			if d>=2: c.followups.append(area(c,target,70,30,.6))
			if d>=4:
				var decoy := area(c,target+direction.orthogonal()*150,55,0,.2)
				decoy.kind = "b05_decoy"
				decoy.fx_color = Color("87cbbc")
				c.followups.append(decoy)
		13:
			c.merge({"range":115.0,"angle":1.6,"coefficient":120},true)
			var bud := child(c,"b05_bud","line",30,.15)
			bud.merge({"origin":origin+direction*85,"target":origin+direction*85,"range":140.0,"width":22.0,"duration":4.0,"anchor_health":float(profile_value.max_hp)*.1,"max_buds":2 if d>=4 else 1,"fires":d>=2},true)
			c.followups.append(bud)
		14:
			c.merge({"shape":"line","range":360.0,"width":24.0,"coefficient":130,"requires_sunlight":true},true)
			if d>=2: c.followups.append(area(c,origin+direction*360,60,40,.15))
			if d>=4: c.followups.append(child(c,"melee","line",130,.8))
		15:
			if not on_network: return basic(profile_value,origin,target)
			c.merge({"kind":"melee","shape":"line","range":200.0,"width":36.0,"coefficient":100,"root_required":true},true)
			if d>=2:
				c.range = 100.0
				var segment := child(c,"melee","line",100,.6)
				segment.origin = origin+direction*100
				segment.target = origin+direction*200
				c.followups.append(segment)
		16:
			c.merge({"kind":"projectile","shape":"line","width":16.0,"range":280.0,"coefficient":45,"projectile_angles":[-22,0,22],"count":3,"speed":430.0,"projectile_radius":8.0,"b05_hit_cap":2,"b05_shells":d>=2},true)
		17:
			c.merge({"kind":"ground_area","shape":"circle","target":origin,"radius":130.0,"coefficient":125},true)
			if d>=2:
				c.shape = "ring"
				c.inner_radius = 65.0
				c.followups.append(area(c,origin,65,125,.65))
			if d>=4:
				var guard := child(c,"b05_root_guard","circle",0,.8)
				guard.root_required = true
				c.followups.append(guard)
		18:
			if not on_network: return basic(profile_value,origin,target)
			c.merge({"kind":"b05_mode","shape":"circle","radius":220.0,"coefficient":0,"duration":6.0,"mode":"shield" if cycle%2==0 else "speed","interruptible":true,"root_required":true},true)
	if number in [3,13]: c["minimum_visible_seconds"] = 1.2 if number==3 else 1.5
	if number==6 or (number==0 and d>=2 and on_network): c["minimum_visible_seconds"] = 1.0
	return timed(geometry(c),float(TELLS[number]),d)

static func child(source: Dictionary, kind: String, shape: String, coefficient: int, delay: float) -> Dictionary:
	var result := source.duplicate(true)
	for key in ["followups","after_motion","status","b05_pull","b05_shells","b05_resin_shove","active","points","paths","delay","remaining"]: result.erase(key)
	result.merge({"kind":kind,"shape":shape,"coefficient":coefficient,"delay":delay,"followups":[],"derived":true,"ability_id":str(source.ability_id)+":follow"},true)
	return result

static func area(source: Dictionary, at: Vector2, radius: float, coefficient: int, delay: float, root_required: bool = false) -> Dictionary:
	var result := child(source,"ground_area","circle",coefficient,delay)
	result.merge({"origin":at,"target":at,"radius":radius,"duration":0.0,"root_required":root_required},true)
	return result

static func slow_area(source: Dictionary, at: Vector2, radius: float, duration: float, delay: float) -> Dictionary:
	var result := area(source,at,radius,0,delay)
	result.merge({"duration":duration,"tick_interval":.5,"status":{"id":"slow","magnitude":.8,"duration":.8}},true)
	return result

static func timed(command: Dictionary, authored: float, difficulty: int, boss: bool = false) -> Dictionary:
	var timing := Timing.boss(authored,.4,difficulty,command,2) if boss else Timing.ordinary(authored,.4,difficulty,command,2)
	timing.tell_seconds=maxf(float(timing.tell_seconds),float(command.get("minimum_visible_seconds",0))-float(timing.lock_seconds))
	command.merge({"timing":timing,"telegraph_seconds":timing.tell_seconds,"locked_seconds":timing.lock_seconds,"tell":timing.tell_seconds,"lock":timing.lock_seconds},true)
	return command

static func freeze_damage(command: Dictionary, profile_value: Dictionary) -> Dictionary:
	var result := command.duplicate(true)
	var source := Numbers.boss(int(profile_value.difficulty),profile_value.get("enemy_calibration_snapshot",{}),int(profile_value.get("b05_numerical_version",1))) if profile_value.enemy_id == "BO05" else Numbers.ordinary(str(profile_value.enemy_id),int(profile_value.enemy_level),int(profile_value.difficulty),str(profile_value.rank),profile_value.get("enemy_calibration_snapshot",{}),int(profile_value.get("b05_numerical_version",1)))
	if source.is_empty() or profile_value.get("damage") != source.damage: return {}
	preload("res://scripts/domain/combat/enemy_power_policy.gd").stamp(result, source)
	result["damage"] = Numbers.skill_damage(source,int(result.get("coefficient",0)),int(result.get("b05_phase",1)),result)
	result["ruleset_version"] = 2
	result["scale_version"] = 10
	result["enemy_command_version"] = 2
	return result

static func boss_action(profile_value: Dictionary, action: String, origin: Vector2, target: Vector2, phase: int, root_positions: Array = []) -> Dictionary:
	var i := BOSS_ACTIONS.find(action)
	if i<0 or int(profile_value.difficulty)<int(BOSS_GATES[i]): return {}
	var c := base(profile_value,origin,target)
	c.merge({"boss_id":"BO05","action_id":action,"ability_id":"BO05:"+action,"ability_name":BOSS_NAMES[i],"ability_name_en":BOSS_NAMES_EN[i],"b05_phase":phase,"cooldown":BOSS_CDS[i],"recovery":2.0,"active":true,"range":360.0,"difficulty":int(profile_value.difficulty)},true)
	var direction: Vector2 = c.direction
	match action:
		"crown_sweep": c.merge({"range":200.0,"angle":deg_to_rad(120),"coefficient":110,"recovery":1.3},true)
		"three_roots":
			c.merge({"shape":"line","width":32.0,"range":360.0,"coefficient":65,"root_sequence":3,"root_interval":.6},true)
		"pod_rain":
			c.merge({"kind":"ground_area","shape":"circle","radius":90.0,"coefficient":70,"targets":[target+direction.orthogonal()*105,target-direction.orthogonal()*105]},true)
		"growth_rings":
			c.merge({"kind":"ground_area","shape":"circle","origin":origin,"target":origin,"radius":150.0,"coefficient":80},true)
			var outer := area(c,origin,300,80,1.0)
			outer.shape = "ring"
			outer.inner_radius = 150.0
			c.followups.append(outer)
		"bloom_transplant": c.merge({"kind":"b05_summon","shape":"circle","radius":45.0,"coefficient":0,"count":2,"max_alive":2,"summon_id":"B05-M02"},true)
		"season_bloom":
			c.merge({"kind":"ground_area","shape":"ring","target":origin,"radius":230.0,"inner_radius":160.0,"coefficient":65},true)
			if not root_positions.is_empty():
				c.origin = root_positions[0]
				c.target = root_positions[0]
			for step in range(1,3):
				var point: Vector2 = root_positions[step%root_positions.size()] if not root_positions.is_empty() else origin
				var wave := area(c,point,230,65,float(step))
				wave.merge({"shape":"ring","inner_radius":160.0},true)
				c.followups.append(wave)
	return timed(geometry(c),float(BOSS_TELLS[i]),int(profile_value.difficulty),true)

static func geometry(command: Dictionary) -> Dictionary:
	if str(command.get("shape",""))=="line" and not command.has("points"):
		command["target"]=Vector2(command.origin)+Vector2(command.direction)*float(command.get("range",90))
		command["points"]=[command.origin,command.target]
	for i in range(command.get("followups",[]).size()): command.followups[i]=geometry(command.followups[i])
	return command

## The codex calls the same executable builder. Cumulative D2/D4 rows show the
## authored addition and its complete selected command, including actual clocks.
static func all_skills(id: String, difficulty: int, resolved: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var source:=Content.enemy(id)
	if source.is_empty(): return result
	for tier in [0,2,4]:
		var p:=profile(id,int(resolved.get("enemy_level",source.introduced_level)),tier,str(resolved.get("rank","normal")),resolved.get("enemy_calibration_snapshot",null),int(resolved.get("b05_numerical_version",0)))
		var command:=active(p,Vector2.ZERO,Vector2(180,0),true)
		var timing: Dictionary=command.timing.duplicate(true)
		timing["cooldown"]=command.cooldown
		var addition: Dictionary=source.skills[str(tier)]
		result.append({"ability_id":command.ability_id+":D"+str(tier),"icon_id":id,"locked":tier>difficulty,"unlocked":tier<=difficulty,"selected":tier<=difficulty,
			"min_difficulty":tier,"name":command.ability_name,"name_en":command.ability_name_en,"effect":addition.source_text,
			"effect_en":str(addition.get("source_text_en",addition.source_text)),"trigger":"D%d累计主动；释放起计CD；打断消耗50%%CD"%tier,
			"trigger_en":"Cumulative active at D%d; cooldown starts on release, half on interruption"%tier,
			"counter":source.counter_and_drop_text,"counter_en":command.counter_cue_en,"command":command,"cooldown":command.cooldown,
			"tell_seconds":command.tell,"lock_seconds":command.lock,"warning_timing":timing})
	return result
