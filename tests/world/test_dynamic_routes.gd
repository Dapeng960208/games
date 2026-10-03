extends SceneTree
## Dynamic routes use bounded matching, deterministic regional descent and
## explicit departure metadata while legacy level-zero routes remain intact.
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
const Routes = preload("res://scripts/domain/world/route_generator.gd")
var checks: int = 0
var failures: int = 0
var longest_us: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _valid(route: Dictionary, origin: String, level: int) -> bool:
	if not route.get("valid",false): return false
	var count: int = Routes.node_count_for_level(level)
	if route.get("departure_level",-1) != level or route.get("node_count",0) != count or route.get("dynamic_version",0) != 1: return false
	if route.get("biome_id","") != origin or route.get("content_version",0) != Catalog.content_version() or route.get("navigation_validated",true) or route.has("candidate_paths"): return false
	var nodes: Array = route.get("nodes",[])
	var roles: Array = Routes.roles_for_length(count)
	if nodes.size() != count: return false
	var rooms: Array = []
	var regions: Array = []
	for index: int in range(count):
		var node: Dictionary = nodes[index]
		var region: String = Routes.biome_for_index(origin,index,count)
		if node.get("node_index",-1) != index or node.get("role","") != roles[index] or node.get("biome_id","") != region: return false
		if node.get("threat_budget",-1) != Routes.budget_for_index(index,count): return false
		if node.get("next_node",-2) != (index+1 if index<count-1 else -1): return false
		if node.get("early_extraction",false) != (roles[index] in ["objective","elite_objective"]): return false
		var room_id: String = str(node.get("room_id",""))
		if Routes.is_template_node(node):
			var definition: Dictionary = Catalog.room(room_id)
			if rooms.has(room_id) or definition.get("biome_id","") != region or not definition.get("role_tags",[]).has(roles[index]): return false
			rooms.append(room_id)
			if not regions.has(region): regions.append(region)
			if not node.get("options",[]).has(room_id): return false
			for option: String in node.options:
				var option_def: Dictionary = Catalog.room(option)
				if option_def.get("biome_id","") != region or not option_def.get("role_tags",[]).has(roles[index]): return false
				if not node.get("previews",{}).has(option) or node.previews[option].get("biome_id","") != region: return false
		else:
			if not node.options.is_empty(): return false
			if roles[index] == "boss":
				if room_id != Catalog.biomes()[region]["boss_id"] or node.get("arena_id","") != Catalog.bosses()[room_id]["arena"]["arena_id"]: return false
			else:
				if room_id != "service_"+str(roles[index]) or not node.get("safe",false): return false
	if rooms != route.get("template_ids",[]) or rooms.size() != count-3: return false
	var expected_regions: int = 1 if count == 6 else (2 if count == 8 else 3)
	if regions.size() != expected_regions: return false
	return true

func _generate(origin: String, seed_value: int, choices: Array, level: int) -> Dictionary:
	var before: int = Time.get_ticks_usec()
	var route: Dictionary = Routes.generate(origin,seed_value,choices,level)
	longest_us = maxi(longest_us,Time.get_ticks_usec()-before)
	return route

func _run() -> void:
	var start: int = Time.get_ticks_msec()
	_check(Routes.node_count_for_level(0) == 8, "level zero retains legacy length")
	for level: int in range(1,21):
		var expected: int = 6 if level < 5 else (8 if level < 10 else (10 if level < 15 else 12))
		_check(Routes.node_count_for_level(level) == expected and Routes.length_for_level(level) == expected,"level boundary " + str(level))
		for origin: String in Catalog.biomes():
			_check(_valid(_generate(origin,271,[],level),origin,level),"every level and region creates a valid route")
	_check(Routes.roles_for_length(7).is_empty(),"unsupported route lengths rejected")
	_check(Routes.biome_for_index("unknown",1,8).is_empty() and Routes.biome_for_index("B01",12,12).is_empty(),"invalid biome schedule query is empty")
	_check(Routes.budget_for_index(-1,8) == -1 and Routes.budget_for_index(8,8) == -1,"invalid budget query rejected")
	_check(Routes.supply_index({}) == -1 and Routes.scan_indices({}).is_empty(),"empty route helpers safe")
	_check(not Routes.generate("B01",1,[],-1).get("valid",true) and not Routes.generate("B01",1,[],21).get("valid",true),"invalid departure levels rejected")
	_check(not Routes.generate("unknown",1,[],15).get("valid",true),"unknown dynamic origin rejected")
	_check(not Routes.generate("B01",1,["L02"],15).get("valid",true),"malformed choices rejected")
	_check(not Routes.generate("B01",1,[{"node_index":0,"room_id":"L02"}],15).get("valid",true),"service choices rejected")
	_check(not Routes.generate("B01",1,[{"node_index":1,"room_id":"L01"}],15).get("valid",true),"incorrect role rejected")
	_check(not Routes.generate("B01",1,[{"node_index":1,"room_id":"L08"}],15).get("valid",true),"foreign region choice rejected")
	_check(not Routes.generate("B01",1,[{"node_index":1,"room_id":"L02"},{"node_index":2,"room_id":"L02"}],15).get("valid",true),"duplicate templates rejected")
	_check(not Routes.generate("B01",1,[{"node_index":1,"room_id":"L02"},{"node_index":1,"room_id":"L03"}],15).get("valid",true),"conflicting constraints rejected")
	for malformed: Variant in [null,[],{},"1",1.5,true,INF,NAN]:
		_check(not Routes.generate("B01",1,[{"node_index":malformed,"room_id":"L02"}],15).get("valid",true),"malformed choice index rejected safely")
	var healthy: Dictionary = Routes.generate("B01",1,[],15)
	for field: String in ["departure_level","dynamic_version","node_count","seed","nodes","choices","biome_id"]:
		var corrupted: Dictionary = healthy.duplicate(true)
		corrupted[field] = null
		_check(not Routes.choose(corrupted,1,str(healthy.nodes[1].room_id)).get("valid",true),"damaged "+field+" rejected safely")
	for bad_node: Variant in [null,1,{"room_id":"L02","options":null},{"options":[]},{}]:
		var corrupted: Dictionary = healthy.duplicate(true)
		corrupted.nodes[1] = bad_node
		_check(not Routes.choose(corrupted,1,str(healthy.nodes[1].room_id)).get("valid",true),"malformed nested node rejected safely")
	for bad_choice: Variant in [{},{"node_index":[],"room_id":"L02"},1,null]:
		var corrupted: Dictionary = healthy.duplicate(true)
		corrupted.choices = [bad_choice]
		_check(not Routes.choose(corrupted,1,str(healthy.nodes[1].room_id)).get("valid",true),"malformed stored choice rejected safely")
	for level: int in [1,4,5,9,10,14,15,20]:
		for origin: String in Catalog.biomes():
			for seed_value: int in range(12):
				var route: Dictionary = _generate(origin,seed_value,[],level)
				var identity: String = origin+"/L"+str(level)+"/"+str(seed_value)
				_check(_valid(route,origin,level),identity+" structurally valid with distinct matching rooms")
				if not route.get("valid",false): continue
				_check(route == _generate(origin,seed_value,[],level),identity+" deterministic complete route")
				var scanned: Array = []
				var supply: int = Routes.supply_index(route)
				for node: Dictionary in route.nodes:
					if not Routes.is_template_node(node): continue
					var index: int = int(node.node_index)
					if index > supply: scanned.append(index)
					for option: String in node.options:
						var chosen: Dictionary = Routes.choose(route,index,option)
						_check(_valid(chosen,origin,level),identity+" every visible choice has a legal full suffix")
						if not chosen.get("valid",false): continue
						_check(chosen.seed == seed_value and chosen.nodes[index].room_id == option,identity+" choice keeps seed and selected room")
						var prefix_same: bool = true
						for previous: int in range(index):
							if chosen.nodes[previous].room_id != route.nodes[previous].room_id: prefix_same = false
						_check(prefix_same,identity+" visited rooms cannot change")
						_check(chosen == _generate(origin,seed_value,chosen.choices,level),identity+" explicit branch decisions replay identically")
				_check(Routes.scan_indices(route) == scanned,identity+" scanning covers exactly post-supply combat rooms")
				_check(not Routes.choose(route,supply,"L02").get("valid",true),identity+" supply cannot be replaced")
				_check(not Routes.choose(route,1,"unknown").get("valid",true),identity+" unoffered option rejected")
				if seed_value == 0:
					var sequential: Dictionary = route
					for index: int in range(route.nodes.size()):
						if Routes.is_template_node(sequential.nodes[index]):
							sequential = Routes.choose(sequential,index,str(sequential.nodes[index].options.back()))
							_check(_valid(sequential,origin,level),identity+" repeated non-default choices complete")
					_check(sequential == _generate(origin,seed_value,sequential.choices,level),identity+" whole chosen route replays")
					var elite_index: int = route.nodes.size()-2
					var future_room: String = str(route.nodes[elite_index].room_id)
					var constrained: Dictionary = _generate(origin,seed_value,[{"node_index":elite_index,"room_id":future_room}],level)
					for option: String in constrained.nodes[1].options:
						var chosen: Dictionary = Routes.choose(constrained,1,option)
						_check(_valid(chosen,origin,level) and chosen.nodes[elite_index].room_id == future_room,identity+" preserves explicit future constraint")
	for seed_value: int in [-1,-9223372036854775807,9223372036854775807]:
		var route: Dictionary = _generate("B04",seed_value,[],20)
		_check(_valid(route,"B04",20) and route == _generate("B04",seed_value,[],20),"full signed seed and biome wrap deterministic")
	seed(472)
	var expected_random: int = randi()
	seed(472)
	Routes.generate("B02",99,[],20)
	_check(randi() == expected_random,"dynamic generation leaves global reward RNG unchanged")
	var legacy: Dictionary = Routes.generate("B01",12)
	_check(legacy == Routes.generate("B01",12,[],0),"omitting departure level retains exact legacy route")
	_check(legacy.nodes.size() == 8 and legacy.has("candidate_paths") and not legacy.has("dynamic_version") and not legacy.has("departure_level") and not legacy.has("node_count"),"legacy save format preserved")
	_check(Routes.supply_index(legacy) == 4 and Routes.scan_indices(legacy) == [5,6],"dynamic helpers accept legacy routes")
	var untouched: Dictionary = _generate("B01",5,[],20)
	var mutable: Dictionary = _generate("B01",5,[],20)
	mutable.nodes[1].options.clear()
	mutable.nodes[1].previews.clear()
	_check(untouched == _generate("B01",5,[],20),"returned data has no shared mutable route cache")
	print("DYNAMIC_ROUTE_TIMING elapsed_ms="+str(Time.get_ticks_msec()-start)+" max_generate_us="+str(longest_us))
	_check(longest_us < 1000000,"every generated route completes in a bounded one second including cold startup")
	print("DYNAMIC_ROUTE_TESTS checks="+str(checks)+" failures="+str(failures))
	quit(0 if failures == 0 else 1)
