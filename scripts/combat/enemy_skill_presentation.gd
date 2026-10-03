extends RefCounted
## Read-only ordinary cast cards and source-stamped ornaments. The gameplay
## command is authoritative; this file never creates damage or advances clocks.
const Catalog = preload("res://scripts/combat/enemy_ability_catalog.gd")
const Properties = preload("res://scripts/combat/combat_properties.gd")
const Text = preload("res://scripts/ui/strings.gd")
const MAX_DETAIL := 2

static func readout(brain: RefCounted) -> Dictionary:
 if brain == null or not brain.has_method("current_skill"): return {}
 var command: Dictionary = brain.call("current_skill")
 if command.is_empty(): return {}
 var info: Dictionary = Catalog.command_info(command,Text.locale == "en")
 var phase: String = str(command.get("phase",""))
 var fraction: float = float(command.get("progress",0.0))
 var tell: float = maxf(0.001,float(command.get("telegraph_seconds",0.55)))
 var lock: float = maxf(0.001,float(command.get("locked_seconds",0.4)))
 info["phase"] = phase
 info["locked"] = bool(command.get("locked",false))
 info["progress"] = (tell+fraction*lock)/(tell+lock) if phase == "locked" else fraction*tell/(tell+lock) if phase == "telegraph" else fraction
 info["remaining"] = float(command.get("remaining",0.0))+(lock if phase == "telegraph" else 0.0)
 info["command"] = command
 return info

static func detail_candidates(room: Node) -> Array[int]:
 var result: Array[int] = []
 if not is_instance_valid(room): return result
 var player: Variant = Properties.read(room,"player")
 var container: Variant = Properties.read(room,"enemies")
 if not player is Node2D or not container is Node: return result
 var target_ref: Variant = Properties.read(player,"_automatic_attack_target")
 var target: Object = target_ref.get_ref() if target_ref is WeakRef else null
 var candidates: Array[Dictionary] = []
 for actor: Node in container.get_children():
  if not actor is Node2D or actor.is_queued_for_deletion() or not actor.has_method("is_alive") or not actor.call("is_alive"): continue
  var brain: Variant = Properties.read(actor,"brain")
  if not brain is RefCounted or not brain.has_method("current_skill"): continue
  var info: Dictionary = brain.call("current_skill")
  if info.is_empty() or str(info.get("phase","")) not in ["telegraph","locked","execute","recovery"]: continue
  var distance: float = actor.position.distance_to(player.position)
  if distance > 380.0 and actor != target: continue
  var score: float = distance - (1000.0 if actor == target else 0.0) - (180.0 if str(info.get("phase","")) == "locked" else 90.0 if str(info.get("phase","")) == "execute" else 0.0)
  candidates.append({"id":actor.get_instance_id(),"score":score})
 candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.score)<float(b.score) if not is_equal_approx(float(a.score),float(b.score)) else int(a.id)<int(b.id))
 for candidate: Dictionary in candidates.slice(0,MAX_DETAIL): result.append(int(candidate.id))
 return result

static func draw_identity(canvas: CanvasItem, identity: String, at: Vector2, radius: float, tint: Color) -> void:
 # Fallbacks use stable source identity, not a different monster's portrait.
 # Six silhouettes × nine inner marks remain distinct even without color.
 var number: int = clampi(int(identity.trim_prefix("B05-M")),1,18)-1 if identity.begins_with("B05-M") else clampi(int(identity.trim_prefix("M")),1,54)-1
 var sides: int = 3+number%6
 var outline := PackedVector2Array()
 for index: int in range(sides+1): outline.append(at+Vector2.from_angle(-PI*.5+TAU*index/sides)*radius)
 canvas.draw_polyline(outline,tint,1.6,true)
 var inner: int = number/6+1
 for index: int in inner:
  var point: Vector2 = at+Vector2((index%3-1)*3.2,(index/3-1)*3.2)
  canvas.draw_circle(point,0.8,tint)

static func _fit(font: Font, value: String, width: float, size: int) -> String:
 if font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x <= width: return value
 var copy: String = value
 while not copy.is_empty() and font.get_string_size(copy+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,size).x > width: copy = copy.substr(0,copy.length()-1)
 return copy+"…"

static func draw_card(canvas: CanvasItem, info: Dictionary, at: Vector2) -> void:
 if info.is_empty(): return
 var english: bool = Text.locale == "en"
 var font: Font = ThemeDB.fallback_font
 var box := Rect2(at,Vector2(254,61))
 canvas.draw_rect(box,Color("fff0d7"))
 canvas.draw_rect(box,Color("b89365"),false,1.0)
 var phase: String = str(info.phase)
 var stages: Dictionary = {"telegraph":"AIM" if english else "蓄力","locked":"LOCK" if english else "锁定","execute":"STRIKE" if english else "出手","recovery":"RECOVER" if english else "收势"}
 var color := Color("ce6655") if bool(info.locked) else Color("886036")
 canvas.draw_string(font,at+Vector2(7,16),_fit(font,str(info.name),240,13),HORIZONTAL_ALIGNMENT_LEFT,240,13,Color("48374b"))
 var status: String = str(stages.get(phase,phase))+"  %d/%d  %.1fs" % [int(info.stage),int(info.stage_count),float(info.remaining)]
 canvas.draw_string(font,at+Vector2(7,31),status,HORIZONTAL_ALIGNMENT_LEFT,240,11,color)
 canvas.draw_string(font,at+Vector2(7,46),_fit(font,str(info.counter),240,11),HORIZONTAL_ALIGNMENT_LEFT,240,11,Color("6d5a55"))
 canvas.draw_rect(Rect2(at+Vector2(7,53),Vector2(240,3)),Color("d5c4a7"))
 canvas.draw_rect(Rect2(at+Vector2(7,53),Vector2(240*clampf(float(info.progress),0,1),3)),color)

static func draw_effect(canvas: Node2D, command: Dictionary, reduced: bool) -> void:
 var id: String = str(command.get("caster_enemy_id",""))
 if id.is_empty(): return
 var at: Vector2 = command.get("origin",Vector2.ZERO)
 if str(command.get("shape","")) == "circle": at = command.get("target",at)
 var color: Color = command.get("fx_color",Color("d49b67"))
 draw_identity(canvas,id,at,6.0 if reduced else 10.0,Color(color,.75))

static func draw_projectile(canvas: Node2D, command: Dictionary, reduced: bool) -> void:
 var id: String = str(command.get("caster_enemy_id",""))
 if id.is_empty(): return
 var at: Vector2 = command.get("position",Vector2.ZERO)
 var direction: Vector2 = command.get("direction",Vector2.RIGHT)
 var color: Color = command.get("fx_color",Color("d49b67"))
 if not reduced: draw_identity(canvas,id,at,maxf(5,float(command.get("radius",5))),color)
 # Return arrows are essential even when ornamental FX are reduced.
 if bool(command.get("returning",false)):
  canvas.draw_polyline(PackedVector2Array([at-direction*7+direction.orthogonal()*4,at,at-direction*7-direction.orthogonal()*4]),Color("fff5d7"),2.0,true)
