extends RefCounted
const Content = preload("res://scripts/levels/b09/world/content.gd")
const Growth = preload("res://scripts/domain/combat/shared_enemy_growth.gd")
const Timing = preload("res://scripts/domain/combat/enemy_warning_timing.gd")
const ARCHETYPES := {"F":"skirmisher", "R":"skirmisher", "C":"caster", "S":"support", "A":"assassin", "T":"tank"}
const CDS := [7,8,7,7,10,12,8,13,9,9,9,11,12,14,11,10,10,13]
const TELLS := [1.0,1.1,1.0,0.9,1.1,1.2,1.0,1.3,1.1,1.0,1.0,1.3,1.3,1.4,1.2,1.3,1.2,1.4]
const BOSS_ACTIONS := ["court_arc","frost_marks","prism_ray","bridge_decree","crown_guards","mirror_verdict","reform"]
const BOSS_GATES := [0,0,1,2,3,4,0]
const BOSS_CDS := [7,12,15,18,20,25,14]
const BOSS_TELLS := [1.2,1.3,1.4,2.0,1.4,1.6,1.5]

static func profile(id: String, level: int, difficulty: int, rank: String = "normal") -> Dictionary:
	var authored := Content.enemy(id)
	if authored.is_empty() or level not in [41,43,45] or difficulty not in range(5) or rank not in ["normal","elite"]: return {}
	var raw: Dictionary = authored.raw_stats
	var archetype: String = ARCHETYPES[authored.profile]
	var result := Growth.stats(raw,archetype,authored.profile,level,9,difficulty,rank)
	result.merge({"enemy_id":id,"name":authored.name,"biome_id":"B09","chapter":9,"clan":"crystal","actor_kind":"enemy","rank":rank,
		"enemy_level":level,"difficulty":difficulty,"ruleset_version":2,"scale_version":10,"mechanic_tier":4,
		"archetype":archetype,"role":authored.profile,"move_speed":minf(132.0,float(raw.move_speed)*(1.0+0.006*(level-1)))*(1.0+0.04*difficulty),
		"navigation_radius":22.0 if authored.profile=="T" else 18.0,"attack_range":raw.attack_range,"recovery_seconds":raw.recovery_seconds,
		"effective_threat_cost":1,"encounter_slot_cost":1,"encounter_budget_cost":1,"encounter_budget":18,"reserved_summon_count":0,"reserved_summon_threat":0,
		"crystal_layers":authored.crystal_layers,"damage_type":"physical","b09_candidate":true},true)
	return result

static func boss_profile(difficulty: int) -> Dictionary:
	if difficulty not in range(5): return {}
	return {"enemy_id":"BO09","boss_id":"BO09","name":"霜晶女王","biome_id":"B09","chapter":9,"clan":"crystal","actor_kind":"boss","rank":"boss","enemy_level":45,
		"difficulty":difficulty,"ruleset_version":2,"scale_version":10,"mechanic_tier":4,"archetype":"caster","crystal_layers":3,
		"max_hp":int(floor(1400*13.5*1.96*[1.0,1.4,2.0,2.8,4.0][difficulty]+0.5)),
		"damage":int(floor(32*13.5*1.64*[1.0,1.2,1.5,1.85,2.3][difficulty]+0.5)),
		"armor":(12+2*difficulty)*10,"magic_resist":(12+2*difficulty)*10,"move_speed":60.0,"navigation_radius":32.0,
		"attack_range":190.0,"recovery_seconds":1.4,"phase_thresholds":[0.7,0.35],"reinforcements":[],"reinforcement_cap":0,"reinforcement_budget":0,"b09_candidate":true}

static func base(p: Dictionary, origin: Vector2, target: Vector2) -> Dictionary:
	var direction := origin.direction_to(target)
	if direction.is_zero_approx(): direction=Vector2.RIGHT
	return {"b09_command":true,"caster_enemy_id":p.enemy_id,"difficulty":p.difficulty,"origin":origin,"target":target,"direction":direction,
		"kind":"melee","shape":"cone","angle":deg_to_rad(90),"range":90.0,"coefficient":100,"damage_multiplier":1.0,
		"recovery":p.recovery_seconds,"cooldown":0.0,"active":false,"followups":[],"stage":0,"ability_id":str(p.enemy_id)+":basic","ability_name":"晶核普攻","ability_name_en":"Crystal strike"}

static func timed(c: Dictionary, duration: float, boss: bool = false) -> Dictionary:
	var value := Timing.boss(duration,0.4,int(c.difficulty),c,2) if boss else Timing.ordinary(duration,0.4,int(c.difficulty),c,2)
	# Authored long interruptible channels and bridge warnings retain their window.
	if bool(c.get("interruptible",false)) or (boss and c.kind=="b09_bridge"): value.tell_seconds=maxf(float(value.tell_seconds),duration-float(value.lock_seconds))
	c.merge({"timing":value,"tell":value.tell_seconds,"lock":value.lock_seconds,"telegraph_seconds":value.tell_seconds,"locked_seconds":value.lock_seconds},true)
	if c.shape=="line" and not c.has("points"): c["points"]=[c.origin,Vector2(c.origin)+Vector2(c.direction)*float(c.range)]
	return c

static func basic(p: Dictionary, origin: Vector2, target: Vector2) -> Dictionary:
	var c := base(p,origin,target)
	if str(p.role) in ["R","C"]:
		c.merge({"kind":"projectile","shape":"line","range":float(p.attack_range),"width":12.0,"radius":6.0,"speed":300.0},true)
	return timed(c,1.0)

static func follow(source: Dictionary, kind: String, shape: String, coefficient: int, delay: float) -> Dictionary:
	var c := source.duplicate(true)
	for key in ["followups","points","paths","status","duration","travel_distance","interruptible","b09_utility"]: c.erase(key)
	c.merge({"kind":kind,"shape":shape,"coefficient":coefficient,"delay":delay,"followups":[],"stage":int(source.stage)+1,"derived":true},true)
	return c

static func area(source: Dictionary, at: Vector2, radius: float, coefficient: int, delay: float) -> Dictionary:
	var c := follow(source,"ground_area","circle",coefficient,delay)
	c.merge({"origin":at,"target":at,"radius":radius,"duration":0.0},true)
	return c

static func active(p: Dictionary, origin: Vector2, target: Vector2) -> Dictionary:
	var n := int(str(p.enemy_id).trim_prefix("B09-M"))-1
	if n not in range(18): return {}
	var c := base(p,origin,target)
	var d := int(p.difficulty)
	var v: Vector2 = c.direction
	c.merge({"active":true,"cooldown":float(CDS[n]),"ability_id":str(p.enemy_id)+":active","ability_name":Content.enemy(p.enemy_id).name+"·主动","range":280.0,"counter_cue":Content.enemy(p.enemy_id).counter_text},true)
	match n+1:
		1:
			c.merge({"range":130.0,"coefficient":110},true)
			if d>=2:
				var ice := area(c,origin+v*115,35,0,0.0)
				ice.merge({"kind":"b09_ice","duration":2.0,"ice_size":Vector2(90,25)},true)
				c.followups.append(ice)
		2:
			c.merge({"kind":"ground_area","shape":"circle","radius":80.0,"coefficient":90,"status":{"id":"slow","duration":2.0,"multiplier":0.85}},true)
			if d>=2: c.followups.append(area(c,target+v.orthogonal()*70,45,30,1.0 if d>=4 else 0.6))
		3:
			c.merge({"kind":"projectile","shape":"line","width":14.0,"speed":300.0,"radius":7.0},true)
			if d>=2:
				var sides := follow(c,"projectile","line",30,0.94)
				sides.merge({"origin":origin+v*280,"count":2,"projectile_angles":[-60,60],"range":100.0},true)
				c.followups.append(sides)
		4,9,17:
			var distance := 180.0 if n==3 else 220.0 if n==16 else 160.0
			c.merge({"kind":"charge","shape":"line","width":34.0,"range":distance,"travel_distance":distance,"target":origin+v*distance,"duration":0.5,"coefficient":85 if n==3 else 115 if n==16 else 50,"b09_stop_on_snow":n==3 or (n==8 and d>=4)},true)
			if n==3 and d>=2:
				var turn := v.rotated(deg_to_rad(60))
				var slide := follow(c,"charge","line",0,0.55)
				slide.merge({"origin":c.target,"direction":turn,"target":Vector2(c.target)+turn*60,"travel_distance":60.0,"range":60.0,"duration":0.3,"b09_stop_on_snow":true},true)
				c.followups.append(slide)
			if n==8:
				var second := follow(c,"charge","line",50,0.6)
				var turn := v.rotated(deg_to_rad(60))
				second.merge({"origin":c.target,"direction":turn,"target":Vector2(c.target)+turn*120,"travel_distance":120.0,"range":120.0,"duration":0.4,"b09_stop_on_snow":d>=4},true)
				c.followups.append(second)
				if d>=2:
					var ice := area(c,second.target,50,0,1.05)
					ice.merge({"kind":"b09_ice","duration":2.0,"ice_size":Vector2(100,100)},true)
					c.followups.append(ice)
			if n==16 and d>=2: c.followups.append(area(c,c.target,75,40,0.65))
		5: c.merge({"kind":"b09_shield","shape":"line","width":110.0,"range":130.0,"coefficient":100,"duration":4.0 if d>=2 else 1.0},true)
		6: c.merge({"kind":"b09_siphon","shape":"circle","radius":40.0,"coefficient":0,"interruptible":true,"duration":4.0},true)
		7:
			var step := origin+v.orthogonal()*70
			c.merge({"kind":"charge","shape":"line","range":220.0,"width":20.0,"travel_distance":70.0,"target":step,"direction":v.orthogonal(),"duration":0.25,"coefficient":0},true)
			var stab := follow(c,"melee","cone",110,0.3)
			stab.merge({"origin":step,"target":target,"direction":step.direction_to(target),"range":150.0,"b09_origin_matches":true},true)
			c.followups.append(stab)
			if d>=2: c.followups.append(area(c,origin,70,30,1.0))
		8:
			c.merge({"kind":"b09_reform_allies","shape":"circle","origin":origin,"target":origin,"radius":260.0,"coefficient":0,"interruptible":true},true)
			if d>=2: c.followups.append(area(c,origin,80,30,0.25))
		10:
			c.merge({"kind":"ground_area","shape":"circle","radius":90.0,"coefficient":95,"delay":1.0},true)
			if d>=2:
				var snow := area(c,target,90,0,0.0)
				snow.merge({"kind":"b09_snow","duration":2.0},true)
				c.followups.append(snow)
			if d>=4: c.followups.append(area(c,target+v.orthogonal()*100,90,95,0.8))
		11:
			c.merge({"kind":"projectile","shape":"line","width":16.0,"radius":8.0,"speed":320.0},true)
			if d>=2:
				var rear := follow(c,"projectile","line",50,0.9)
				rear.merge({"direction":-v,"target":origin-v*280,"points":[origin,origin-v*280]},true)
				c.followups.append(rear)
		12:
			c.merge({"kind":"b09_wall","shape":"circle","radius":60.0,"width":120.0,"coefficient":70,"duration":4.0,"gap":100.0 if d>=4 else 0.0},true)
			if d>=2: c["shatter"]=area(c,target,60,40,0.0)
		13:
			c.merge({"kind":"ground_area","shape":"circle","origin":origin,"target":origin,"radius":135.0,"coefficient":125},true)
			if d>=2:
				var ring := area(c,origin,190,40,1.0)
				ring.merge({"shape":"ring","inner_radius":145.0},true)
				c.followups.append(ring)
		14: c.merge({"kind":"b09_bridge","shape":"circle","radius":70.0,"coefficient":0,"interruptible":true},true)
		15:
			c.merge({"kind":"ground_area","shape":"circle","origin":origin,"target":origin,"radius":95.0,"coefficient":55},true)
			var outer := area(c,origin,185,55,1.0)
			outer.merge({"shape":"ring","inner_radius":110.0,"ring_gap_degrees":70.0 if d>=2 else 0.0,"ring_gap_angle":v.angle()},true)
			c.followups.append(outer)
		16:
			c.merge({"kind":"projectile","shape":"line","width":14.0,"speed":400.0,"radius":7.0,"refraction_points":[origin+v*130+v.orthogonal()*80],"points":[origin,origin+v*130+v.orthogonal()*80,target]},true)
			if d>=2: c.followups.append(area(c,c.refraction_points[0],60,30,1.0))
		18:
			c.merge({"kind":"ground_area","shape":"circle","radius":85.0,"coefficient":65},true)
			c.followups.append(area(c,target+v.orthogonal()*120,85,65,0.9))
			if d>=2:
				var support := area(c,origin,260,0,0.95)
				support.merge({"kind":"b09_reform_allies","max_targets":1},true)
				c.followups.append(support)
	c["stage_count"]=c.followups.size()+1
	return timed(c,float(TELLS[n]))

static func boss_action(p: Dictionary, action: String, origin: Vector2, target: Vector2, phase: int) -> Dictionary:
	var i := BOSS_ACTIONS.find(action)
	if i<0 or int(p.difficulty)<BOSS_GATES[i]: return {}
	var c := base(p,origin,target)
	c.merge({"active":true,"action_id":action,"ability_id":"BO09:"+action,"ability_name":["王庭剑弧","双落霜印","棱镜射线","断桥王令","冠晶侍卫","三镜裁决","晶面重组"][i],"cooldown":float(BOSS_CDS[i]),"b09_phase":phase,"recovery":1.4},true)
	var v: Vector2 = c.direction
	match action:
		"court_arc": c.merge({"range":190.0,"angle":deg_to_rad(110),"coefficient":115},true)
		"frost_marks":
			c.merge({"kind":"ground_area","shape":"circle","radius":90.0,"coefficient":75,"range":600.0},true)
			c.followups.append(area(c,target+v.orthogonal()*150,90,75,0.9))
		"prism_ray": c.merge({"kind":"projectile","shape":"line","range":600.0,"width":18.0,"radius":9.0,"speed":400.0,"refraction_points":[origin+v*150+v.orthogonal()*110],"points":[origin,origin+v*150+v.orthogonal()*110,target]},true)
		"bridge_decree": c.merge({"kind":"b09_bridge","shape":"circle","radius":80.0,"range":900.0,"coefficient":0},true)
		"crown_guards": c.merge({"kind":"b09_summon","shape":"circle","radius":45.0,"range":900.0,"coefficient":0},true)
		"mirror_verdict":
			c.merge({"range":350.0,"angle":deg_to_rad(70),"coefficient":65,"recovery":2.5,"b09_mirror":true},true)
			for stage in [1,2]:
				var next := follow(c,"melee","cone",65,1.1*stage)
				next.merge({"direction":v.rotated(deg_to_rad(120*stage)),"stage":stage},true)
				c.followups.append(next)
		"reform": c.merge({"kind":"b09_reform","shape":"circle","origin":origin,"target":origin,"radius":70.0,"coefficient":0,"interruptible":true},true)
	c["stage_count"]=c.followups.size()+1
	return timed(c,float(BOSS_TELLS[i]),true)

static func freeze(c: Dictionary, p: Dictionary) -> Dictionary:
	var result := c.duplicate(true)
	var boss := str(p.rank)=="boss"
	var factor: float = [1.0,1.06,1.12,1.2,1.3][int(p.difficulty)]*[1.0,1.1,1.2][int(c.get("b09_phase",1))-1] if boss else 1.25*[1.0,1.05,1.1,1.15,1.2][int(p.difficulty)]
	result.merge({"damage":int(floor(float(p.damage)*float(c.get("coefficient",0))/100.0*factor+0.5)),"ruleset_version":2,"scale_version":10,"enemy_command_version":2},true)
	return result
