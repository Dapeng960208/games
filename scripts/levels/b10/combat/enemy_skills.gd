extends RefCounted
## The final court uses the existing warning, collision and damage paths. All
## coordinates are room ground coordinates; body illustration anchors are visual.
const Growth = preload("res://scripts/domain/combat/shared_enemy_growth.gd")
const Timing = preload("res://scripts/domain/combat/enemy_warning_timing.gd")
const Props = preload("res://scripts/domain/combat/combat_properties.gd")
const ARCHETYPES := {"F":"skirmisher","R":"skirmisher","C":"caster","S":"support","A":"assassin","T":"tank"}
static var _data: Dictionary = {}

static func catalog() -> Dictionary:
	if _data.is_empty():
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/b10/combat.json"))
		if value is Dictionary: _data = value
	return _data

static func enemy_definition(id: String) -> Dictionary:
	return catalog().get("enemies",{}).get(id,{}).duplicate(true)

static func enemy_ids() -> Array:
	return catalog().get("enemies",{}).keys()

static func boss_definition(id: String) -> Dictionary:
	return catalog().get("bosses",{}).get(id,{}).duplicate(true)

static func is_boss(id: String) -> bool:
	return catalog().get("bosses",{}).has(id)

static func profile(id: String, level: int, difficulty: int, rank: String = "normal", calibration: Variant = null) -> Dictionary:
	var source := enemy_definition(id)
	if source.is_empty() or difficulty not in range(5) or level not in [46,48,50] or rank not in ["normal","elite"]: return {}
	var raw: Dictionary = source.raw_stats.duplicate(true)
	var archetype: String = ARCHETYPES[source.profile]
	var values := Growth.stats(raw,archetype,source.profile,level,10,difficulty,rank)
	if values.is_empty(): return {}
	var result := source.duplicate(true)
	result.merge(values,true)
	result.merge({"chapter":10,"enemy_level":level,"rank":rank,"difficulty":difficulty,"ruleset_version":2,"scale_version":10,
		"archetype":archetype,"primary_role":{"F":"warrior","R":"ranged","C":"caster","S":"support","A":"assassin","T":"tank"}[source.profile],
		"move_speed":minf(132,float(raw.move_speed)*(1+.006*(level-1)))*(1+.04*difficulty),"attack_range":float(raw.attack_range),
		"recovery_seconds":1.3 if source.profile in ["S","T"] else 1.15,"navigation_radius":24.0 if source.profile=="T" else 18.0,
		"damage_type":"magic" if source.profile in ["C","S"] else "physical","behavior_id":"b10_"+str(id).to_lower(),
		"effective_threat_cost":source.threat_cost,"attack_parameters":{"summon_cap":0,"range":raw.attack_range},
		"difficulty_mechanics":{"difficulty":difficulty},"mechanics":["star_core","locked_target"],"gameplay_implemented":true,"b10_combat_version":1},true)
	if calibration is Dictionary: result["enemy_calibration_snapshot"] = calibration.duplicate(true)
	return result

static func boss_profile(id: String, difficulty: int, calibration: Variant = null) -> Dictionary:
	var source := boss_definition(id)
	if source.is_empty() or difficulty not in range(5): return {}
	var final_boss := id=="BO10"
	var hp := int(round(float(source.raw_hp)*1.35*10*2.08*Growth.HP_D[difficulty]))
	var attack := int(round(float(source.raw_damage)*1.35*10*1.72*Growth.ATTACK_D[difficulty]))
	var result := source.duplicate(true)
	result.merge({"enemy_id":id,"biome_id":"B10","chapter":10,"clan":"dragon","actor_kind":"boss","rank":"boss","enemy_level":int(source.level),
		"max_hp":hp,"damage":attack,"armor":(15+2*difficulty)*10,"magic_resist":(15+2*difficulty)*10,
		"move_speed":54.0 if final_boss else 68.0,"navigation_radius":float(source.radius),"attack_range":360.0,
		"recovery_seconds":1.5,"difficulty":difficulty,"ruleset_version":2,"scale_version":10,"mechanic_tier":4,
		"phase_thresholds":[.7,.35],"immune_forced_movement":true,"effective_threat_cost":0.0,
		"reinforcement_cap":4 if final_boss and difficulty>=3 else 0,"reinforcement_budget":4 if final_boss and difficulty>=3 else 0,
		"reinforcement_waves":[],"reserved_summon_count":0,"reserved_summon_threat":0.0,"encounter_budget":18,
		"damage_type":"magic","visual_asset":art_id(id),"gameplay_implemented":true,"b10_combat_version":1},true)
	if calibration is Dictionary: result["enemy_calibration_snapshot"] = calibration.duplicate(true)
	return result

static func art_id(id: String) -> String:
	if id.begins_with("B10-M"): return "asset://level.b10.enemies.m%02d.body"%int(id.trim_prefix("B10-M"))
	if id.begins_with("B10-D"): return "asset://level.b10.bosses.d%02d.body"%int(id.trim_prefix("B10-D"))
	return "asset://level.b10.bosses.bo10.body"

static func runtime(actor: Node2D) -> Variant:
	return Props.read(Props.read(Props.read(actor,"room"),"enemy_skills"),"b10")

static func connected(actor: Node2D) -> bool:
	var extension: Variant = runtime(actor)
	return extension is Object and extension.connected(actor)

static func base(p: Dictionary, origin: Vector2, target: Vector2) -> Dictionary:
	var direction := origin.direction_to(target)
	if direction.is_zero_approx(): direction=Vector2.RIGHT
	return {"b10_command":true,"caster_enemy_id":p.enemy_id,"ability_id":str(p.enemy_id)+":basic","ability_name":"龙鳞击","ability_name_en":"Draconic Strike",
		"counter_cue":"离开已锁定区域；破核后接近","counter_cue_en":"Leave the locked shape; break the core and approach during recovery",
		"origin":origin,"target":target,"direction":direction,"kind":"melee","shape":"cone","range":95.0,"angle":1.8,"coefficient":100,
		"damage_type":p.get("damage_type","physical"),"fx_color":Color("e79351"),"cooldown":0.0,"recovery":1.15,"followups":[],"difficulty":int(p.difficulty),"b10_phase":1}

static func timed(c: Dictionary, seconds: float, difficulty: int, boss: bool = false) -> Dictionary:
	var timing := Timing.boss(seconds,.4,difficulty,c,2) if boss else Timing.ordinary(seconds,.4,difficulty,c,2)
	# Final-court area attacks always have a readable combined warning window.
	timing.tell_seconds=maxf(float(timing.tell_seconds),seconds*.8-float(timing.lock_seconds))
	c.merge({"timing":timing,"tell":timing.tell_seconds,"lock":timing.lock_seconds,"telegraph_seconds":timing.tell_seconds,"locked_seconds":timing.lock_seconds},true)
	return geometry(c)

static func basic(p: Dictionary, origin: Vector2, target: Vector2) -> Dictionary:
	var c := base(p,origin,target)
	if p.profile in ["R","C","S"]:
		c.merge({"kind":"projectile","shape":"line","range":float(p.attack_range),"width":16.0,"speed":360.0,"projectile_radius":7.0,"count":1},true)
	return timed(c,.85,int(p.difficulty))

static func child(c: Dictionary, kind: String, shape: String, coefficient: int, delay: float) -> Dictionary:
	var result := c.duplicate(true)
	for key in ["followups","active","points","paths","duration","remaining","timing","status","b10_echo","b10_target_refs","b10_frozen","damage"]: result.erase(key)
	result.merge({"kind":kind,"shape":shape,"coefficient":coefficient,"delay":delay,"followups":[],"derived":true,"ability_id":str(c.ability_id)+":follow"},true)
	return result

static func area(c: Dictionary, at: Vector2, radius: float, coefficient: int, delay: float) -> Dictionary:
	var result := child(c,"ground_area","circle",coefficient,delay)
	result.merge({"origin":at,"target":at,"radius":radius,"duration":0.0},true)
	return result

static func active(p: Dictionary, origin: Vector2, target: Vector2, on_core: bool = false, cycle: int = 0) -> Dictionary:
	var source := enemy_definition(str(p.enemy_id))
	if source.is_empty(): return {}
	var n := int(str(p.enemy_id).trim_prefix("B10-M"))
	var d := int(p.difficulty)
	var c := base(p,origin,target)
	c.merge({"ability_id":str(p.enemy_id)+":active","ability_name":source.action_name,"ability_name_en":source.name_en+" Active","active":true,
		"cooldown":float(source.cooldown),"range":float(p.attack_range),"on_core":on_core,"interruptible":source.profile=="S"},true)
	var direction: Vector2 = c.direction
	match n:
		1:
			c.merge({"range":150.0,"angle":2.0,"coefficient":110},true)
			if d>=2 and on_core: c.followups.append(child(c,"b10_stance","circle",0,.1))
		2:
			var distance := minf(220,origin.distance_to(target))
			c.merge({"kind":"charge","shape":"line","range":distance,"target":origin+direction*distance,"travel_distance":distance,"width":42.0,"radius":75.0,
				"coefficient":95,"duration":.5,"landing_only":true,"landing_shape":"circle","recovery":1.3},true)
			if d>=2:
				var shot := child(c,"projectile","line",30,.65)
				shot.merge({"origin":c.target,"target":c.target+direction*200,"range":200.0,"speed":280.0,"width":14.0,"count":1,"projectile_radius":7.0},true)
				c.followups.append(shot)
		3:
			c.merge({"kind":"ground_area","shape":"circle","radius":85.0,"coefficient":100,"b10_echo":d>=2 and on_core},true)
		4:
			c.merge({"kind":"projectile","shape":"line","range":340.0,"width":16.0,"coefficient":110,"speed":430.0,"projectile_radius":7.0,"count":1},true)
			if d>=2: c.followups.append(child(c,"b10_reposition","circle",0,.3))
			if d>=4: c.followups.append(child(c,"b10_stance","circle",0,0))
		5:
			c.merge({"kind":"b10_transfer","shape":"circle","coefficient":0,"radius":40.0,"range":360.0,"target_count":1,"haste_duration":2.0 if d>=2 else 0.0},true)
		6:
			c.merge({"kind":"b10_guard","coefficient":0,"range":115.0,"guard_duration":1.0 if d>=4 and not on_core else 2.0},true)
			var bash := child(c,"melee","cone",100,float(c.guard_duration))
			bash.merge({"range":115.0,"angle":1.8},true)
			c.followups.append(bash)
			if d>=2:
				var line := child(c,"ground_area","line",30,float(c.guard_duration)+.25)
				line.merge({"range":110.0,"width":22.0,"duration":.75,"tick_interval":1.0},true)
				c.followups.append(line)
		7:
			var middle:=origin+direction*115+direction.orthogonal()*55
			var finish:=origin+direction*230
			c.merge({"kind":"charge","shape":"line","range":origin.distance_to(middle),"travel_distance":origin.distance_to(middle),"target":middle,"direction":origin.direction_to(middle),"width":40.0,"radius":22.0,"coefficient":110,"duration":.3,"recovery":1.5,"b10_swept_cast":true},true)
			var second:=child(c,"charge","line",110,.35)
			second.merge({"origin":middle,"target":finish,"direction":middle.direction_to(finish),"range":middle.distance_to(finish),"travel_distance":middle.distance_to(finish),"duration":.3},true)
			c.followups.append(second)
			if d>=2:
				var sweep := child(c,"melee","cone",40,.85)
				sweep.merge({"origin":finish,"target":finish-direction*90,"direction":-direction,"range":90.0,"angle":2.3,"b10_swept_cast":false},true)
				c.followups.append(sweep)
		8:
			c.merge({"kind":"ground_area","shape":"circle","radius":72.0,"coefficient":60,"target":target-direction.orthogonal()*80},true)
			c.followups.append(area(c,target+direction.orthogonal()*80,72,60,1.0))
			if d>=2:
				var marker:=child(c,"b10_waymark","circle",0,1.0)
				marker.merge({"origin":target+direction*100,"target":target+direction*100,"radius":42.0,"harmless":true},true)
				c.followups.append(marker)
		9:
			c.merge({"kind":"projectile","shape":"line","range":320.0,"width":18.0,"coefficient":100,"count":1,"speed":380.0,"projectile_radius":8.0},true)
			if d>=2:
				var trail := child(c,"ground_area","line",30,.45)
				trail.merge({"origin":target-direction*80,"target":target,"range":80.0,"width":20.0,"duration":1.0,"tick_interval":1.0},true)
				c.followups.append(trail)
		10:
			c.merge({"kind":"b10_repair","shape":"circle","coefficient":0,"radius":40.0,"range":360.0},true)
		11:
			c.merge({"shape":"line","width":38.0,"range":220.0,"coefficient":120,"recovery":1.8 if d>=4 and not on_core else 1.3},true)
			if d>=2:
				for side in [-1,1]: c.followups.append(area(c,origin+direction*170+direction.orthogonal()*65*side,35,30,.5))
		12:
			c.merge({"shape":"ring","range":180.0,"radius":180.0,"inner_radius":85.0,"origin":origin,"target":origin,"ring_gap_degrees":90.0,"coefficient":90,"b10_echo":d>=2 and on_core},true)
			if d>=4: c.followups.append(child(c,"b10_reposition","circle",0,1.1))
		13:
			c.merge({"range":155.0,"angle":1.7,"coefficient":60},true)
			var second_slash:=child(c,"melee","cone",60,.9)
			second_slash["b10_relock"]=true
			c.followups.append(second_slash)
			if d>=2 and on_core: c.followups.append(child(c,"b10_stance","circle",0,1.05))
		14:
			c.merge({"shape":"line","range":300.0,"width":30.0,"coefficient":100,"b10_cross_gate":true},true)
			if d>=2: c.followups.append(area(c,target,45,30,.5))
		15:
			c.merge({"kind":"ground_area","shape":"circle","radius":95.0,"coefficient":115,"recovery":2.0},true)
			if d>=2:
				for side in [-1,1]:
					var fragment := child(c,"projectile","line",30,.2)
					fragment.merge({"origin":target,"target":target+direction.orthogonal()*side*190,"direction":direction.orthogonal()*side,"range":190.0,"speed":250.0,"width":16.0,"count":1,"projectile_radius":7.0},true)
					c.followups.append(fragment)
		16:
			c.merge({"kind":"b10_harmonize","shape":"circle","coefficient":0,"radius":40.0,"range":360.0,"target_count":2},true)
		17:
			c.merge({"kind":"ground_area","shape":"circle","origin":origin,"target":origin,"radius":95.0,"coefficient":70},true)
			var outer := area(c,origin,185,70,1.1)
			outer.merge({"shape":"ring","inner_radius":105.0},true)
			c.followups.append(outer)
			if d>=2:
				var stone := child(c,"b10_scale_stone","circle",0,.4)
				stone.merge({"target":origin-direction*115,"radius":22.0,"anchor_health":roundf(float(p.max_hp)*.15)},true)
				c.followups.append(stone)
		18:
			c.merge({"kind":"ground_area","shape":"circle","radius":62.0,"coefficient":55,"target":target-direction.orthogonal()*105},true)
			c.followups.append(area(c,target,62,55,1.0))
			var last := area(c,target+direction.orthogonal()*105,62,55,2.0)
			last["core_required"] = d>=4
			c.followups.append(last)
			if d>=2 and on_core: c.followups.append(child(c,"b10_stance","circle",0,2.1))
	return timed(c,float(source.tell),d)

static func geometry(c: Dictionary) -> Dictionary:
	if str(c.shape)=="line" and not c.has("points"):
		c.target=Vector2(c.origin)+Vector2(c.direction)*float(c.range)
		c["points"]=[c.origin,c.target]
	if str(c.kind)=="ground_area" and str(c.shape) in ["circle","ring"]: c.origin=c.target
	for i in c.get("followups",[]).size(): c.followups[i]=geometry(c.followups[i])
	return c

static func freeze_damage(c: Dictionary, p: Dictionary) -> Dictionary:
	if not bool(p.get("b10_combat_version",false)): return {}
	if bool(c.get("b10_frozen",false)): return c.duplicate(true)
	var result := c.duplicate(true)
	var phase := clampi(int(result.get("b10_phase",1)),1,3)
	var factor: float = (1.0+.075*int(p.difficulty))*(1.0+.1*(phase-1)) if str(p.rank)=="boss" else 1.25*(1.0+.05*int(p.difficulty))
	result["damage"] = int(round(float(p.damage)*float(result.get("coefficient",0))/100.0*factor))
	result.merge({"ruleset_version":2,"scale_version":10,"enemy_command_version":2,"b10_frozen":true},true)
	return result

static func encounter_plan(room_id: String, zone_index: int, difficulty: int, calibration: Variant = null) -> Dictionary:
	var index := int(room_id.trim_prefix("L"))-55
	if index not in range(6) or zone_index!=0 or difficulty not in range(5): return {}
	var waves: Array=[]
	for wave in range(3):
		var batch: Array=[]
		for offset in range(3):
			var id := "B10-M%02d"%(index*3+offset+1)
			var source := enemy_definition(id)
			var p := profile(id,int(source.level),difficulty,"elite" if difficulty>=3 and wave==2 and offset==0 else "normal",calibration)
			p.merge({"zone_index":0,"wave_index":wave,"encounter_budget":18,"encounter_budget_cost":p.effective_threat_cost,"encounter_slot_cost":1,"reserved_summon_count":0,"reserved_summon_threat":0},true)
			batch.append(p)
		waves.append(batch)
	return {"room_id":room_id,"zone_index":0,"waves":waves,"total_count":9,"concurrent_cap":3,"concurrent_threat_budget":18,"reinforce_alive_threshold":0,"reinforce_threat_fraction":0.0,"reinforce_delay_seconds":1.5,"difficulty":difficulty}
