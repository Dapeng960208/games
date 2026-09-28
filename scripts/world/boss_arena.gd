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
	var labels: Dictionary = {"cooling_valve":"冷却阀 · 关闭一条火道","root_knot":"根瘤 · 击碎以缩小毒潮","fuse_box":"供电匣 · 击碎以关闭航道","edge_bell":"边缘鸣钟 · 击碎以削弱回声"}
	var assets: Dictionary = {"cooling_valve":"B01_winch","root_knot":"B02_spore_nest","fuse_box":"B03_transformer","edge_bell":"B04_resonance_obelisk"}
	for counter: Dictionary in layout.get("boss_counterplay",[]):
		var id: String = str(counter.id)
		var kind: String = str(counter.kind)
		var extra: Dictionary = counter.duplicate(true)
		extra["required"] = false
		if bool(counter.get("breakable",false)):
			add_target(id,counter.position,48.0,str(assets[kind]),str(labels[kind]),extra)
		else:
			extra["repeatable"] = true
			add_element(id,counter.position,str(labels[kind]),kind,str(assets[kind]),extra)
	queue_redraw()

func interact(id: String, actor: Node2D) -> bool:
	if not elements.has(id) or not is_instance_valid(boss) or not boss.is_alive(): return false
	var item: Dictionary = elements[id]
	if bool(item.get("breakable",false)) or actor.position.distance_to(item.position)>100 or not room.has_line_of_sight(actor.position,item.position): return false
	if not boss.apply_arena_counter(id,item): return false
	item["description"] = "该方向接下来两轮喷火被关闭"
	room.add_ring(item.position,Color("8be0c4"),70,.6)
	return true

func on_target_destroyed(id: String) -> void:
	if elements.has(id):
		elements[id].done = true
		elements[id]["destroyed"] = true
		if is_instance_valid(boss) and boss.is_alive(): boss.apply_arena_counter(id,elements[id])
	targets.erase(id)
	queue_redraw()

func navigation_target() -> Dictionary:
	return {"position":boss.position if is_instance_valid(boss) else layout.exit,"title":"击败首领 · 利用场边装置削弱招式","kind":"encounter"}

func status() -> Dictionary:
	return {"title":room_id,"text":"利用场边机关破坏首领攻势","completed":0,"required":1,"complete":false,"quality":"full","optional":""}
