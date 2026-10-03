extends Node2D
## Optional safe practice uses the production projectile and damage paths.
var room: Node2D
var target: Node2D
var timer: float = 1.8
var font: Font

func configure(host: Node2D) -> void:
	room = host
	font = load(AssetCatalog.resolve("asset://fonts/NotoSansSC.ttf"))
	target = room.spawn_enemy(Vector2(1280,650),"M03",1,{"reward_enabled":false,"actor_kind":"training"})
	if is_instance_valid(target):
		target.training_ai_disabled = true
		target.state = &"chase"
		target.health.reset(1600.0)
		target.move_speed = 0.0
		target.static_actor = true
	z_index = 6

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target) or not target.is_alive():
		queue_redraw()
		return
	if not room.controls_enabled() or room.player.position.distance_to(target.position) > 800.0:
		return
	timer -= delta
	if timer <= 0.0:
		timer = 1.8
		var direction: Vector2 = target.position.direction_to(room.player.position)
		target.aim_direction = direction
		room.enemy_skills.emit_skill(target,{"kind":"projectile","origin":target.position,"target":room.player.position,"direction":direction,"damage":0.0,"speed":260.0,"range":950.0})
	queue_redraw()

func _draw() -> void:
	if font == null: return
	var at := Vector2(1280,650)
	var alive: bool = is_instance_valid(target) and target.is_alive()
	var english: bool = Words.locale == "en"
	draw_arc(at,48,0,TAU,36,Color("99d6d5"),1.5,true)
	var label: String = ("Optional target · No damage or loot" if english else "可选练习靶 · 无伤弹道 · 无掉落") if alive else ("Practice complete" if english else "练习完成")
	_centered_label(label,at+Vector2(0,-86),17,Color("f3e6bc"))
	# Leaving never requires killing this high-health practice target.
	_centered_label("M · Choose a room and depart anytime" if english else "随时按 M 选关出发 · 无需击败练习靶",at+Vector2(0,105),16,Color("f3e6bc"))
	if alive:
		_centered_label("C · Place two anchors → V · Discharge" if english else "C 布两桩拦弹 → V 释放",at+Vector2(0,80),16,Color("b4efdf"))
		if room.circuit.anchors.size() < 2:
			for marker: Vector2 in [Vector2(1220,560),Vector2(1220,820)]:
				draw_arc(marker,18,0,TAU,24,Color(0.6,0.9,0.84,0.65),1.5,true)
				draw_string(font,marker+Vector2(-5,6),"C",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("b4efdf"))

func _centered_label(text: String, at: Vector2, size: int, tint: Color) -> void:
	var origin := at-Vector2(font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x*0.5,0)
	draw_string_outline(font,origin,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,3,Color("102027"))
	draw_string(font,origin,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,tint)
