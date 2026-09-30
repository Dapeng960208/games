extends "res://scripts/world/room_objectives.gd"
## Physical arena countermeasures share the player's real basic-attack path.
var boss: Node2D

func configure_boss_arena(owner_room: Node2D, arena_layout: Dictionary, actor: Node2D) -> void:
	reset()
	room = owner_room
	layout = arena_layout.duplicate(true)
	boss = actor
	room_id = str(actor.boss_id)
	objective_font = load("res://assets/fonts/NotoSansSC.ttf")
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material = WorldArt.material_for(str(layout.get("biome_id", "B01")))
	definition = {"biome_id":str(layout.get("biome_id","B01"))}
	var labels: Dictionary = {"cooling_valve":"能源回路 · 接通破除首领护盾","root_knot":"育虫卵囊 · 击碎停止孵化","fuse_box":"墓穴封印 · 封闭减少复生","edge_bell":"战鼓拒马 · 击碎削弱狂怒"}
	var descriptions: Dictionary = {"cooling_valve":"E 接通能源，破除护盾并暴露核心弱点；短暂冷却后可再次使用","root_knot":"普攻击碎卵囊，阻止孵化并暴露腹部弱点","fuse_box":"E 封闭墓穴，阻止该墓地继续复生","edge_bell":"普攻击碎战鼓或引冲锋撞碎，消除狂怒并露出弱点"}
	var themes: Dictionary = {"cooling_valve":"solar_conduit","root_knot":"brood_egg","fuse_box":"grave_seal","edge_bell":"war_drum"}
	var assets: Dictionary = {"cooling_valve":"B01_winch","root_knot":"B02_spore_nest","fuse_box":"B03_transformer","edge_bell":"B04_resonance_obelisk"}
	for counter: Dictionary in layout.get("boss_counterplay",[]):
		var id: String = str(counter.id)
		var kind: String = str(counter.kind)
		var extra: Dictionary = counter.duplicate(true)
		extra["required"] = false
		extra["thematic_counter"] = str(themes.get(kind,""))
		extra["description"] = str(descriptions.get(kind,""))
		extra["counter_cooldown"] = 0.0
		extra["breakable"] = bool(counter.get("breakable",false)) and kind!="fuse_box"
		if bool(extra.breakable):
			add_target(id,counter.position,48.0,str(assets[kind]),str(labels[kind]),extra)
		else:
			extra["repeatable"] = kind=="cooling_valve"
			add_element(id,counter.position,str(labels[kind]),kind,str(assets[kind]),extra)
	queue_redraw()

func interact(id: String, actor: Node2D) -> bool:
	if (is_inside_tree() and get_tree().paused) or not elements.has(id) or not is_instance_valid(boss) or not boss.is_alive() or not is_instance_valid(actor): return false
	var item: Dictionary = elements[id]
	if bool(item.get("breakable",false)) or not bool(item.get("interactive",true)) or float(item.get("counter_cooldown",0))>0 or (bool(item.get("done",false)) and not bool(item.get("repeatable",false))) or actor.position.distance_to(item.position)>100 or not room.has_line_of_sight(actor.position,item.position): return false
	if not boss.apply_arena_counter(id,item): return false
	if str(item.get("thematic_counter",""))=="solar_conduit":
		item.counter_cooldown = 12.0
		item.interactive = false
		item.phase = "充能冷却 · 12秒"
	else:
		item.done = true
		item.interactive = false
		item.phase = "已封闭"
	event("boss_arena_counter_applied",{"id":id,"kind":str(item.get("thematic_counter",""))})
	room.add_ring(item.position,Color("8be0c4"),70,.6)
	return true

func tick(delta: float) -> void:
	if delta<=0 or not is_finite(delta) or (is_inside_tree() and get_tree().paused): return
	super.tick(delta)
	for item: Dictionary in elements.values():
		if float(item.get("counter_cooldown",0))<=0: continue
		item.counter_cooldown = maxf(0,float(item.counter_cooldown)-delta)
		item.phase = "充能冷却 · %d秒" % ceili(float(item.counter_cooldown))
		if float(item.counter_cooldown)<=0:
			item.interactive = true
			item.phase = "可接通"

func on_target_destroyed(id: String) -> void:
	if elements.has(id):
		if bool(elements[id].get("done",false)): return
		elements[id].done = true
		elements[id]["destroyed"] = true
		if is_instance_valid(boss) and boss.is_alive(): boss.apply_arena_counter(id,elements[id])
	targets.erase(id)
	queue_redraw()

func notify_charge_impact(caster: Node2D, from: Vector2, to: Vector2) -> Dictionary:
	if not is_instance_valid(boss) or caster!=boss or str(boss.boss_id)!="BO04" or not boss.is_alive() or (is_inside_tree() and get_tree().paused): return {"success":false}
	var destroyed := 0
	var motion: Vector2 = to-from
	if motion.length()<12: return {"success":false}
	for id: String in targets.keys():
		var target: Node2D = targets[id]
		if not is_instance_valid(target) or not target.is_alive(): continue
		var progress: float = clampf((target.position-from).dot(motion)/motion.length_squared(),0,1)
		if target.position.distance_to(from+motion*progress)>64: continue
		target.take_damage(float(target.health.maximum)+1,&"arena_charge",motion.normalized(),{"damage_type":"true"})
		if bool(elements[id].get("done",false)): destroyed += 1
	return {"success":destroyed>0,"destroyed":destroyed}

func navigation_target() -> Dictionary:
	return {"position":boss.position if is_instance_valid(boss) else layout.exit,"title":"击败首领 · 利用场边装置削弱招式","kind":"encounter"}

func status() -> Dictionary:
	var text: String = str({"BO01":"接通能源回路破盾，攻击显露的辉炉核心","BO02":"击碎卵囊停止孵化，趁腹部弱点进攻","BO03":"封闭墓穴减少复生，再清理首领与复生敌人","BO04":"拆毁战鼓或诱导冲锋撞墙，趁失衡破除护甲"}.get(room_id,"利用场边机关破坏首领攻势"))
	var english: String = str({"BO01":"Charge conduits to break the shield, then attack the exposed core","BO02":"Break brood eggs to stop hatching and expose the abdomen","BO03":"Seal graves to limit resurrection, then defeat the boss and returned enemies","BO04":"Break war drums or lure a charge into the walls, then exploit the stagger"}.get(room_id,"Use arena devices to counter the boss"))
	if Words.locale=="en": text = english
	return {"title":room_id,"text":text,"text_en":english,"rules":"first_four_boss_v1","completed":0,"required":1,"complete":false,"quality":"full","optional":""}
