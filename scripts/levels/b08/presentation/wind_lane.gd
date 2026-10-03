extends RefCounted
## Candidate flow marks. Presentation reads room-local state; it never changes it.
const FLOW_INK := Color(.16,.33,.43,.90)
const FLOW_EDGE := Color(.97,.96,.91,.90)
const WARNING_EDGE := Color("784323")
const WARNING_INK := Color("efa13f")
static func marks(rect: Rect2, direction: Vector2, time: float, reduced: bool) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array]=[]
	var safe:=rect.grow(-4)
	var tangent:=direction.normalized()
	var cross:=tangent.orthogonal()
	var rows:=maxi(1,floori(rect.size.y/40))
	var columns:=maxi(1,floori(rect.size.x/62))
	for row in rows:
		for column in columns:
			var seed: float=float(row*7+column*3)
			var center:=rect.position+Vector2((column+.5)*rect.size.x/columns,(row+.5)*rect.size.y/rows)
			if not reduced: center+=tangent*(fposmod(time*25+seed*7,28)-14)
			var start:=center-tangent*12+cross*2
			var middle:=center-tangent*3-cross*2
			var tip:=center+tangent*12
			var plume:=tip-tangent*6+cross*3
			var line:=PackedVector2Array([start,middle,tip,plume])
			var inside:=true
			for point: Vector2 in line:
				if not safe.has_point(point): inside=false; break
			if inside: result.append(line)
	return result
static func draw_lane(canvas: Node2D, lane: Dictionary, wind: RefCounted, time: float, reduced: bool) -> void:
	var direction: Vector2=wind.direction(lane.id,lane.direction)
	for mark: PackedVector2Array in marks(lane.rect,direction,time,reduced):
		canvas.draw_polyline(mark,FLOW_EDGE,3.6,true)
		canvas.draw_polyline(mark,FLOW_INK,2.0,true)
	if wind.pending.get("lane","")!=lane.id: return
	# Only the actual one-second switch warning uses an amber border and future direction.
	canvas.draw_rect(lane.rect.grow(-2),WARNING_EDGE,false,3.6)
	canvas.draw_rect(lane.rect.grow(-2),WARNING_INK,false,2.0)
	for mark: PackedVector2Array in warning_marks(lane,wind):
		canvas.draw_polyline(mark,WARNING_EDGE,4.0,true)
		canvas.draw_polyline(mark,WARNING_INK,2.2,true)
static func warning_marks(lane: Dictionary, wind: RefCounted) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array]=[]
	if wind.pending.get("lane","")!=lane.id: return result
	var modes: Array[Vector2]=[lane.direction,-lane.direction,Vector2(lane.direction).orthogonal()]
	var future: Vector2=modes[int(wind.pending.mode)]
	var center: Vector2=lane.rect.get_center()
	for offset: int in [-22,0,22]:
		var tip: Vector2=center+future*12+future.orthogonal()*offset
		var tail: Vector2=tip-future*24
		if lane.rect.grow(-4).has_point(tip) and lane.rect.grow(-4).has_point(tail):
			result.append(PackedVector2Array([tail,tip-future*5+future.orthogonal()*2,tip,tip-future*6-future.orthogonal()*3]))
	return result
