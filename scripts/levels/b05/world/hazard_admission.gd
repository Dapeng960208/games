extends RefCounted
## Conservative whole-command reservations. No scene state or chapter registration.
const Geometry=preload("res://scripts/levels/b05/world/room_geometry.gd")
var room_id:=""
var floor_polygon:=PackedVector2Array()
var protected_routes: Array[PackedVector2Array]=[]
var effective_area:=0.0
var maximum_ratio:=0.3
var reservations: Dictionary={}
var clock:=0.0
func configure(id: String) -> bool:
	var definition:=Geometry.room(id)
	if definition.is_empty(): return false
	room_id=id;floor_polygon=Geometry.polygon(id);effective_area=Geometry._area(floor_polygon)
	for obstacle: PackedVector2Array in Geometry.obstacles(id):
		for cut: PackedVector2Array in Geometry2D.intersect_polygons(obstacle,floor_polygon): effective_area-=Geometry._area(cut)
	for key: String in ["main_route","safe_route"]:
		var width: float=float(definition.get(key+"_width_world",180 if key=="main_route" else 140))
		protected_routes.append_array(Geometry2D.offset_polyline(Geometry.route(id,key),width*.5+14.0,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND))
	maximum_ratio=float(definition.maximum_active_hazard_area_ratio)
	return effective_area>0 and not protected_routes.is_empty()
func advance(delta: float) -> void:
	if not is_finite(delta) or delta<0: return
	clock+=delta
	for id: String in reservations.keys():
		if float(reservations[id].expires)<=clock: reservations.erase(id)
func cancel(id: String) -> void: reservations.erase(id)
func admitted(id: String) -> bool: return reservations.has(id) and float(reservations[id].expires)>clock
func admit(command: Dictionary,id: String,allow_reposition: bool=true) -> Dictionary:
	var original:=command.duplicate(true)
	original["b05_admission_id"]=id
	if id.is_empty() or room_id.is_empty(): return _reject(original,"missing identity or room")
	var variants: Array[Dictionary]=[original]
	if allow_reposition:
		var pivot: Vector2=original.get("origin",Vector2.ZERO)
		for degrees in [45,-45,90,-90,135,-135,180]: variants.append(_transform(original,pivot,deg_to_rad(degrees),Vector2.ZERO))
		# Only detached ground commands may translate; physical caster attacks keep their origin.
		if str(original.get("kind",""))=="ground_area":
			for offset: Vector2 in [Vector2(120,0),Vector2(-120,0),Vector2(0,120),Vector2(0,-120),Vector2(240,0),Vector2(-240,0),Vector2(0,240),Vector2(0,-240)]:
				variants.append(_transform(original,pivot,0,offset))
	for candidate: Dictionary in variants:
		var footprints:=describe(candidate)
		if footprints.is_empty() and _harmful(candidate): continue
		if not _allowed(footprints,id): continue
		_tag(candidate,id,true)
		reservations[id]={"footprints":footprints,"expires":clock+_lifetime(candidate)}
		return candidate
	reservations.erase(id)
	return _reject(original,"safe routes or thirty-percent area budget")
func _reject(command: Dictionary,reason: String) -> Dictionary:
	_tag(command,str(command.get("b05_admission_id","")),false)
	command["b05_admission_reason"]=reason
	return command
func _tag(command: Dictionary,id: String,accepted: bool) -> void:
	command["b05_admission_id"]=id;command["b05_admitted"]=accepted
	for follow: Dictionary in command.get("followups",[]): _tag(follow,id,accepted)
func _allowed(footprints: Array[Dictionary],excluding: String) -> bool:
	var all: Array[Dictionary]=footprints.duplicate()
	for id: String in reservations:
		if id!=excluding and admitted(id): all.append_array(reservations[id].footprints)
	var total:=0.0
	for footprint: Dictionary in all:
		var polygon: PackedVector2Array=footprint.polygon
		if polygon.size()<3: return false
		for point: Vector2 in polygon:
			if not point.is_finite(): return false
		if Geometry2D.triangulate_polygon(polygon).is_empty(): return false
		if bool(footprint.persistent):
			for route: PackedVector2Array in protected_routes:
				if not Geometry2D.intersect_polygons(polygon,route).is_empty(): return false
		for clipped: PackedVector2Array in Geometry2D.intersect_polygons(polygon,floor_polygon): total+=Geometry._area(clipped)
	return total<=effective_area*maximum_ratio
static func _harmful(command: Dictionary) -> bool:
	return int(command.get("coefficient",0))>0 or not command.get("status",{}).is_empty() or str(command.get("kind","")) in ["b05_bud","b05_shell"]
static func describe(command: Dictionary,depth: int=0) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if depth>8: return result
	var kind:=str(command.get("kind","melee"))
	var persistent:=float(command.get("duration",0))>0 and kind not in ["charge","projectile"]
	persistent=persistent or not command.get("status",{}).is_empty()
	if _harmful(command):
		var origin: Vector2=command.get("origin",Vector2.ZERO)
		var target: Vector2=command.get("target",origin)
		var direction: Vector2=command.get("direction",Vector2.RIGHT)
		var shape:=str(command.get("shape","cone"))
		var radius:=maxf(1,float(command.get("radius",command.get("range",90))))
		if kind=="projectile":
			var angles: Array=command.get("projectile_angles",[0])
			for index in angles.size():
				var end:=origin+direction.rotated(deg_to_rad(float(angles[index])))*float(command.get("range",280))
				_add_line(result,origin,end,maxf(float(command.get("width",16))*.5,float(command.get("projectile_radius",8))),false)
				if bool(command.get("b05_shells",false)) and index!=1: _add_line(result,origin,end,60,true)
		elif kind=="charge":
			var end:=origin+direction*minf(float(command.get("travel_distance",180)),origin.distance_to(target))
			_add_line(result,origin,end,maxf(float(command.get("width",36))*.5,radius),false)
			_add_circle(result,end,radius,false)
			var after:=str(command.get("after_motion",""));var difficulty:=int(command.get("difficulty",0))
			if after=="moss" and difficulty>=2: _add_line(result,origin,end,15,true)
			if after=="leaf" and difficulty>=2: _add_line(result,end,end+direction*200,8,false)
			if after=="roll" and difficulty>=2:
				var rebound: Vector2=command.get("rebound_point",end-direction*110)
				_add_line(result,end,rebound,24,false)
				if difficulty>=4: _add_circle(result,rebound,38,true)
		elif shape in ["circle","ring"]:
			var centers: Array=command.get("targets",[target if kind in ["ground_area","b05_bud"] else origin])
			for center: Vector2 in centers: _add_circle(result,center,radius,persistent)
		elif shape=="line":
			var points: Array=command.get("points",[origin,origin+direction*float(command.get("range",90))])
			for index in range(points.size()-1): _add_line(result,points[index],points[index+1],maxf(1,float(command.get("width",24))*.5),persistent)
		else:
			var polygon:=PackedVector2Array([origin]);var angle:=float(command.get("angle",1.8))
			for index in range(17): polygon.append(origin+direction.rotated(-angle*.5+angle*index/16.0)*float(command.get("range",90)))
			result.append({"polygon":polygon,"persistent":persistent})
		if kind=="b05_bud" and bool(command.get("fires",false)):
			_add_circle(result,target,float(command.get("range",140)),true)
	for follow: Dictionary in command.get("followups",[]): result.append_array(describe(follow,depth+1))
	return result
static func _add_circle(output: Array[Dictionary],at: Vector2,radius: float,persistent: bool) -> void:
	var polygon:=PackedVector2Array()
	# Circumscribed24-gon never underestimates a circular footprint.
	for index in range(24): polygon.append(at+Vector2.from_angle(TAU*index/24.0)*(radius/cos(PI/24.0)))
	output.append({"polygon":polygon,"persistent":persistent})
static func _add_line(output: Array[Dictionary],a: Vector2,b: Vector2,radius: float,persistent: bool) -> void:
	if a.distance_squared_to(b)<0.001: _add_circle(output,a,radius,persistent);return
	var direction:=a.direction_to(b);var side:=direction.orthogonal()*radius
	# Conservative square end caps contain all rounded contact caps.
	output.append({"polygon":PackedVector2Array([a-direction*radius-side,b+direction*radius-side,b+direction*radius+side,a-direction*radius+side]),"persistent":persistent})
static func _transform(command: Dictionary,pivot: Vector2,angle: float,offset: Vector2) -> Dictionary:
	var result:=command.duplicate(true)
	for key: String in ["origin","target","rebound_point"]:
		if result.get(key) is Vector2: result[key]=pivot+(Vector2(result[key])-pivot).rotated(angle)+offset
	if result.get("direction") is Vector2: result.direction=Vector2(result.direction).rotated(angle)
	for key: String in ["points","targets"]:
		if not result.has(key): continue
		for index in result[key].size(): result[key][index]=pivot+(Vector2(result[key][index])-pivot).rotated(angle)+offset
	if result.has("paths"):
		for path: Array in result.paths:
			for index in path.size(): path[index]=pivot+(Vector2(path[index])-pivot).rotated(angle)+offset
	for index in result.get("followups",[]).size(): result.followups[index]=_transform(result.followups[index],pivot,angle,offset)
	return result
static func _lifetime(command: Dictionary) -> float:
	var tail:=maxf(0,float(command.get("delay",0)))+maxf(0,float(command.get("duration",0)))
	for follow: Dictionary in command.get("followups",[]): tail=maxf(tail,_lifetime(follow))
	return maxf(1.0,float(command.get("tell",0))+float(command.get("lock",0))+tail+2.0)
