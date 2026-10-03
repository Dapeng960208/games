extends RefCounted
## Released chapter ornaments only. Warning geometry and frozen commands own damage.
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const MAX_EFFECT_EXTENT := 160.0
static var _manifests: Dictionary = {}

static func frame(boss: String, action: String, kind: String = "effect") -> Dictionary:
	if (boss == "BO05" and not Rules.chapter_enabled(5)) or (boss == "BO06" and not Rules.chapter_enabled(6)) or boss not in ["BO05","BO06"]: return {}
	if not _manifests.has(boss):
		var path := "asset://levels/"+boss.to_lower().replace("bo","b")+"/bosses/"+boss.to_lower()+"/skill_art.json"
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path))) if FileAccess.file_exists(AssetCatalog.resolve(path)) else null
		_manifests[boss] = raw if raw is Dictionary and raw.get("schema_version") == 1 else {}
	var spec: Dictionary = _manifests[boss].get("actions",{}).get(action,{}).get(kind,{})
	if spec.is_empty() or not spec.get("region") is Array or spec.region.size() != 4: return {}
	var texture := Sampler.sampled(str(spec.get("texture","")))
	if texture == null: return {}
	var region := Rect2(float(spec.region[0]),float(spec.region[1]),float(spec.region[2]),float(spec.region[3]))
	if not region.has_area() or not Rect2(Vector2.ZERO,texture.get_size()).encloses(region): return {}
	return {"texture":texture,"texture_path":str(spec.texture),"region":region,"alpha128_bounds":spec.alpha128_bounds}

static func fitted(frame_data: Dictionary, extent: float) -> Vector2:
	var size: Vector2 = frame_data.region.size
	return size*minf(extent/size.x,extent/size.y)

static func draw_icon(canvas: CanvasItem, boss: String, action: String, at: Vector2, extent: float) -> bool:
	var source := frame(boss,action,"icon")
	if source.is_empty(): return false
	var size := fitted(source,extent)
	canvas.draw_texture_rect_region(source.texture,Rect2(at-size*.5,size),source.region)
	return true

static func draw_release(canvas: Node2D, info: Dictionary, reduced: bool) -> bool:
	if reduced or str(info.get("stage","")) != "release": return false
	var source := frame(str(info.get("boss_id","")),str(info.get("action_id","")))
	if source.is_empty(): return false
	# Summons have no impact flash, so their arrival ornament uses the same
	# release clock as the actual boss body. Other effects use frozen impacts.
	if str(info.action_id) not in ["bloom_transplant","coral_escort"]: return false
	_draw(canvas,source,Vector2(0,-40),110.0,1.0-float(info.progress))
	return true

static func draw_impact(canvas: Node2D, command: Dictionary, reduced: bool) -> bool:
	if reduced: return false
	var source := frame(str(command.get("boss_id","")),str(command.get("action_id","")))
	if source.is_empty(): return false
	var origin: Vector2 = command.get("origin",Vector2.ZERO)
	var at: Vector2 = origin
	match str(command.get("shape","")):
		"line":
			var points: Array = command.get("points",[])
			var direction: Vector2 = command.get("direction",Vector2.RIGHT)
			# Respect the runtime's selected line and obstruction clipping.
			at = Vector2(points[0]).lerp(Vector2(points[-1]),.35) if points.size() >= 2 else origin+direction*float(command.get("range",200))*.35
		"circle": at = command.get("target",origin)
		"ring":
			var center: Vector2 = command.get("target",origin)
			# Leave the ring's safe center and warning edge unobscured.
			at = center+Vector2.DOWN*(float(command.get("inner_radius",0))+float(command.get("radius",180)))*.5
		"cone": at = origin+Vector2(command.get("direction",Vector2.RIGHT))*float(command.get("range",180))*.45
	var opacity := clampf(float(command.get("remaining",.22))/.22,0.0,1.0)*.8
	_draw(canvas,source,at,MAX_EFFECT_EXTENT,opacity)
	return true

static func _draw(canvas: CanvasItem, source: Dictionary, at: Vector2, extent: float, opacity: float) -> void:
	var size := fitted(source,extent)
	canvas.draw_texture_rect_region(source.texture,Rect2(at-size*.5,size),source.region,Color(1,1,1,opacity))
