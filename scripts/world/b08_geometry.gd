extends RefCounted
## Seven fixed floor unions, built in blueprint pixels and scaled exactly once.
## Rectangles are debug topology, not replacement environment artwork.
const SCALE := 0.58
const Content = preload("res://scripts/world/b08_content.gd")
const FLOORS := {
	"L43":[[180,540,780,740],[840,750,1120,400],[1840,540,780,740],[760,280,1400,380],[680,460,400,480],[1720,460,400,480]],
	"L44":[[450,250,1900,1300]],
	"L45":[[250,260,2300,1260]],
	"L46":[[200,280,2400,1240]],
	"L47":[[350,1040,2100,500],[350,260,2100,500],[610,650,400,500],[1790,650,400,500]],
	"L48":[[220,250,650,1300],[1930,250,650,1300],[700,300,1400,400],[700,720,1400,400],[700,1150,1400,400]],
	"BO08":[[970,260,860,1320],[200,410,640,800],[1960,410,640,800],[710,660,410,400],[1680,660,410,400]]}
const ENTRY := {"L43":[380,960],"L44":[1400,1380],"L45":[470,1310],"L46":[400,900],"L47":[1400,1390],"L48":[420,900],"BO08":[1400,1390]}
const EXIT := {"L43":[2410,960],"L44":[1400,420],"L45":[2320,450],"L46":[2400,900],"L47":[1400,410],"L48":[2390,480],"BO08":[1400,430]}
# Each lane has a clearly separated normal-speed parallel path.
const LANES := {
	"L43":[[880,325,1150,220]],"L44":[[720,400,240,1000]],
	"L45":[[850,440,1100,220]],"L46":[[750,410,1250,240]],
	"L47":[[660,740,230,460]],"L48":[[900,360,1100,220]],
	"BO08":[[730,690,330,220],[1740,690,330,220]]}
static func point(value: Array) -> Vector2: return Vector2(value[0],value[1])*SCALE
static func rect(value: Array) -> Rect2: return Rect2(value[0]*SCALE,value[1]*SCALE,value[2]*SCALE,value[3]*SCALE)
static func floors(id: String) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for values: Array in FLOORS.get(id,[]): result.append(rect(values))
	return result
static func lanes(id: String) -> Array:
	var result: Array = []
	var index := 0
	for values: Array in LANES.get(id,[]):
		var shape := rect(values)
		result.append({"id":"lane_%d"%index,"rect":shape,"direction":Vector2.DOWN if shape.size.y>shape.size.x else Vector2.RIGHT,"vane":point([840,900]) if id=="L43" else shape.get_center()})
		index += 1
	return result
static func contains(id: String, at: Vector2, radius: float = 0) -> bool:
	if not at.is_finite() or not is_finite(radius) or radius < 0: return false
	var shapes := floors(id)
	for sample: int in range(9):
		var p := at if sample==8 else at+Vector2.RIGHT.rotated(sample*TAU/8)*radius
		var inside := false
		for shape: Rect2 in shapes:
			if shape.has_point(p): inside = true; break
		if not inside: return false
	return true
static func move(id: String, from: Vector2, offset: Vector2, radius: float) -> Vector2:
	if not contains(id,from,radius) or not offset.is_finite(): return from
	var result := from
	var steps := maxi(1,ceili(offset.length()/6.0))
	var step := offset/steps
	for _index in steps:
		var candidate := result+step
		if contains(id,candidate,radius): result = candidate
		elif contains(id,result+Vector2(step.x,0),radius): result.x += step.x
		elif contains(id,result+Vector2(0,step.y),radius): result.y += step.y
	return result
static func lane_at(id: String, at: Vector2) -> Dictionary:
	for lane: Dictionary in lanes(id):
		if lane.rect.has_point(at): return lane
	return {}
