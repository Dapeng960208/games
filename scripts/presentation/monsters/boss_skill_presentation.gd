extends RefCounted
## Read-only cast UI and faction ornaments. Frozen combat geometry owns damage.
const Catalog = preload("res://scripts/domain/combat/boss_ability_catalog.gd")
const SkillArt = preload("res://scripts/presentation/monsters/boss_skill_art.gd")
const Text = preload("res://scripts/infrastructure/localization/strings.gd")
const BASIC_ATTACKS := ["hammer_fan","root_fork","capacitor_burst","resonance_ring"]

static func readout(brain: RefCounted) -> Dictionary:
	var warning: Dictionary = brain.current_telegraph()
	# Load the optional UI helper after autoload initialization. Enemy runtime
	# also serves standalone SceneTree checks, before Game can be resolved.
	var timing: Dictionary = (load(AssetCatalog.resolve("res://scripts/presentation/monsters/enemy_telegraphs.gd")) as Script).presentation_data(warning)
	var action := str(brain.current_action)
	var pose: Dictionary = brain.action_presentation()
	return {"title":Catalog.title(action,Text.locale == "en"),"casting":not warning.is_empty(),"stage":str(pose.get("stage","idle")),"basic":action in BASIC_ATTACKS,"locked":bool(warning.get("locked",false)),"remaining":maxf(0,float(brain.state_time))+(0.0 if bool(warning.get("locked",false)) else float(warning.get("lock",0))),"progress":float(timing.get("release_progress",0)) if not warning.is_empty() else float(pose.get("progress",0)),"boss_id":str(brain.boss_id),"action_id":action,"difficulty":int(brain.definition.get("difficulty",0)),"unlocked":Catalog.unlocked(str(brain.boss_id),int(brain.definition.get("difficulty",0))).size(),"pool":brain.skill_pool().size(),"weakpoint":brain.weakpoint_open()}

static func cast_text(info: Dictionary) -> String:
	var english := Text.locale == "en"
	if str(info.stage) == "idle":
		return ("Skills %d · +%d unlocked" if english else "技库 %d · 难度解锁 +%d") % [int(info.pool),int(info.unlocked)]
	var stages := {"telegraph":"AIMING" if english else "蓄力","locked":"LOCKED" if english else "锁定","release":"STRIKE" if english else "出手","recovery":"RECOVER" if english else "收势"}
	var category := ("Attack · " if english else "普攻 · ") if bool(info.basic) else ("Skill · " if english else "技能 · ")
	return category+str(info.title)+" · "+str(stages.get(str(info.stage),""))+" %.1fs" % float(info.remaining)

static func cast_rect(info: Dictionary, font: Font, at: Vector2) -> Rect2:
	var width := font.get_string_size(cast_text(info),HORIZONTAL_ALIGNMENT_LEFT,-1,16).x+48
	return Rect2(at+Vector2(-width*.5,-28),Vector2(width,40))

static func draw_cast(canvas: CanvasItem, info: Dictionary, font: Font, at: Vector2) -> void:
	var tint: Color = Catalog.COLORS.get(str(info.boss_id),Color("d4ad67"))
	var text := cast_text(info)
	var box := cast_rect(info,font,at)
	var width := box.size.x
	canvas.draw_style_box(GameStyle.box(Color("fff2d6"),Color("ba9256"),1),box)
	var color := Color("d85d49") if bool(info.locked) else tint.darkened(.2)
	if not SkillArt.draw_icon(canvas,str(info.boss_id),str(info.get("action_id","")),box.position+Vector2(20,15),24):
		draw_glyph(canvas,str(info.boss_id),box.position+Vector2(20,15),10,color,0)
	canvas.draw_string(font,box.position+Vector2(38,21),text,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("49364f"))
	if str(info.stage) != "idle":
		canvas.draw_rect(Rect2(box.position+Vector2(8,32),Vector2(width-16,3)),Color("d9c8ad"))
		canvas.draw_rect(Rect2(box.position+Vector2(8,32),Vector2((width-16)*clampf(float(info.progress),0,1),3)),color)

static func body_pose(info: Dictionary) -> Dictionary:
	var aim: Vector2 = info.get("direction",Vector2.RIGHT)
	aim = aim.normalized()
	var p: float = float(info.get("progress",0))
	var strength := 0.0
	match str(info.get("stage","")):
		"telegraph": strength = -smoothstep(0,1,p)
		"locked": strength = -1.0
		"release": strength = 1.0-smoothstep(0,1,p)*0.45
		"recovery": strength = (1.0-smoothstep(0,1,p))*0.55
	var slam: bool = str(info.get("action_id","")) in ["resonance_ring","alternating_ring","heart_crack","crag_leap"]
	return {"offset":Vector2(aim.x*4,-strength*7) if slam else aim*strength*10,"rotation":aim.x*strength*0.10,"scale":Vector2(-0.04,0.055)*strength}

static func draw_action(canvas: Node2D, info: Dictionary, reduced: bool) -> void:
	if info.is_empty(): return
	var stage: String = info.stage
	var p: float = info.progress
	var color: Color = Catalog.COLORS.get(str(info.boss_id),Color("d4ad67"))
	var aim: Vector2 = info.direction
	var center := Vector2(0,-60)
	if stage in ["telegraph","locked"]:
		color.a = 0.38 if reduced else 0.65
		var at := center+aim*42
		draw_glyph(canvas,str(info.boss_id),at,10+5*p,color,0)
		canvas.draw_line(at-aim*20,at-aim*7,color,2,true)
		return
	if stage != "release": return
	if SkillArt.draw_release(canvas,info,reduced): return
	color.a = (1.0-p)*(0.45 if reduced else 0.9)
	var angle := aim.angle()
	if str(info.action_id) in ["resonance_ring","alternating_ring","heart_crack","crag_leap"]:
		canvas.draw_set_transform(Vector2(0,22),0,Vector2(1,.40))
		canvas.draw_arc(Vector2.ZERO,48+p*48,0,TAU,36,color,3 if reduced else 5,true)
		canvas.draw_set_transform(Vector2.ZERO)
	elif str(info.kind) in ["projectile","ground_area"]:
		for index in (1 if reduced else 3):
			var side := float(index-1)*0.24 if not reduced else 0.0
			var direction := aim.rotated(side)
			canvas.draw_line(center+direction*40,center+direction*(66+p*46),color,3,true)
	else:
		canvas.draw_arc(center,58+p*34,angle-.75,angle+.75,24,color,3 if reduced else 6,true)

static func draw_glyph(canvas: CanvasItem, boss_id: String, at: Vector2, radius: float, tint: Color, phase: float) -> void:
	var sides: int = {"BO01":8,"BO02":5,"BO03":6,"BO04":4}.get(boss_id,6)
	var polygon := PackedVector2Array()
	for index: int in sides*2:
		var angle := index*TAU/(sides*2)+phase
		var reach := radius if index%2 == 0 else radius*.65
		polygon.append(at+Vector2.from_angle(angle)*reach)
	polygon.append(polygon[0])
	canvas.draw_polyline(polygon,Color("fff5db"),4,true)
	canvas.draw_polyline(polygon,tint,2,true)
	if boss_id == "BO01": canvas.draw_arc(at,radius*.4,0,TAU,24,tint,2,true)
	elif boss_id == "BO02": canvas.draw_line(at-Vector2(0,radius*.6),at+Vector2(0,radius*.6),tint,2,true)
	elif boss_id == "BO03":
		canvas.draw_line(at-Vector2(radius*.5,0),at+Vector2(radius*.5,0),tint,2,true)
		canvas.draw_line(at-Vector2(0,radius*.5),at+Vector2(0,radius*.5),tint,2,true)
	else: canvas.draw_polyline(PackedVector2Array([at+Vector2(-radius*.4,-radius*.5),at+Vector2(radius*.15,0),at+Vector2(-radius*.1,radius*.5)]),tint,2,true)

static func draw_impact(canvas: Node2D, command: Dictionary, reduced: bool) -> void:
	var id := str(command.get("boss_id",""))
	if id.is_empty() or reduced: return
	if SkillArt.draw_impact(canvas,command,reduced): return
	var at: Vector2 = command.get("origin",Vector2.ZERO)
	var color: Color = command.get("fx_color",Catalog.COLORS.get(id,Color("d4ad67")))
	var radius := minf(32,float(command.get("radius",28))*.4)
	draw_glyph(canvas,id,at,maxf(14,radius),color,0)
