class_name RoomMotif
extends RefCounted
## Original vector inlays and seals. Coordinates are normalized around the
## origin so the room floor and its small paper emblem share a silhouette.

static func ring(c: CanvasItem, at: Vector2, radius: float, ink: Color, width: float = .018) -> void:
	c.draw_arc(at,radius,0,TAU,64,ink,width,true)

static func line(c: CanvasItem, points: Array, ink: Color, width: float = .018) -> void:
	var path := PackedVector2Array()
	for at: Vector2 in points: path.append(at)
	c.draw_polyline(path,ink,width,true)

static func petal(c: CanvasItem, at: Vector2, angle: float, length: float, ink: Color) -> void:
	var points := PackedVector2Array()
	for i: int in 33:
		var a: float = float(i)*TAU/32
		points.append(at+Vector2(cos(a)*length*.50,sin(a)*length*.23).rotated(angle))
	c.draw_colored_polygon(points,Color(ink,.13))
	c.draw_polyline(points,ink,.014,true)

static func star(c: CanvasItem, count: int, inner: float, outer: float, ink: Color, rotation: float = 0) -> void:
	var points := PackedVector2Array()
	for i: int in count*2+1:
		points.append(Vector2.from_angle(rotation-PI*.5+i*PI/count)*(outer if i%2==0 else inner))
	c.draw_colored_polygon(points,Color(ink,.10))
	c.draw_polyline(points,ink,.018,true)

static func draw(c: CanvasItem, key: String, ink: Color, gold: Color) -> void:
	match key:
		"sunburst":
			ring(c,Vector2.ZERO,.58,ink)
			ring(c,Vector2.ZERO,.43,gold)
			for i: int in 12:
				var d := Vector2.from_angle(i*TAU/12)
				line(c,[d*.63,d*.88],gold,.026)
			line(c,[Vector2(0,-.34),Vector2.ZERO,Vector2(.26,.14)],ink,.034)
		"lens_bridge":
			for y: float in [-.44,.44]:
				line(c,[Vector2(-.98,y),Vector2(.98,y)],gold,.030)
			for x: float in [-.65,0,.65]:
				line(c,[Vector2(x,-.58),Vector2(x+.23,0),Vector2(x,.58),Vector2(x-.23,0),Vector2(x,-.58)],ink,.020)
		"season_rings":
			for i: int in 3:
				var at := Vector2.from_angle(-PI*.5+i*TAU/3)*.45
				ring(c,at,.39,ink)
				star(c,4+i,.08,.18,gold,float(i)*.35)
		"orbit":
			ring(c,Vector2.ZERO,.30,gold,.028)
			for i: int in 3:
				var a: float = float(i)*PI/3
				var points := PackedVector2Array()
				for j: int in 65: points.append(Vector2(cos(j*TAU/64)*.90,sin(j*TAU/64)*.42).rotated(a))
				c.draw_polyline(points,ink,.016,true)
				c.draw_circle(Vector2(.90,0).rotated(a),.06,gold)
		"lift_tracks":
			for x: float in [-.54,.54]:
				line(c,[Vector2(x,-.94),Vector2(x,.94)],gold,.032)
				for y: float in [-.7,-.35,0,.35,.7]: line(c,[Vector2(x-.12,y),Vector2(x+.12,y)],ink)
			for i: int in 4: petal(c,Vector2.from_angle(i*PI*.5)*.30,i*PI*.5,.65,ink)
		"triskelion":
			ring(c,Vector2.ZERO,.22,gold,.026)
			for i: int in 3:
				var d := Vector2.from_angle(-PI*.5+i*TAU/3)
				petal(c,d*.52,d.angle(),.74,ink)
				line(c,[d*.24,d*.88],gold)
		"crown_sun":
			star(c,12,.65,.96,gold)
			ring(c,Vector2.ZERO,.58,ink,.028)
			star(c,6,.15,.38,ink)
		"honeycomb":
			for at: Vector2 in [Vector2.ZERO,Vector2(-.54,-.30),Vector2(.54,-.30),Vector2(0,.60),Vector2(0,-.60)]:
				var points := PackedVector2Array()
				for i: int in 7: points.append(at+Vector2.from_angle(PI/6+i*TAU/6)*.35)
				c.draw_colored_polygon(points,Color(gold,.13))
				c.draw_polyline(points,ink,.018,true)
		"wing":
			for side: float in [-1,1]:
				petal(c,Vector2(side*.42,-.30),side*-.6,.94,ink)
				petal(c,Vector2(side*.35,.36),side*.6,.70,gold)
			line(c,[Vector2(0,-.86),Vector2(0,.84)],gold,.045)
		"nursery":
			for at: Vector2 in [Vector2(-.46,-.38),Vector2(.46,-.38),Vector2(0,.42)]:
				petal(c,at,-PI*.5,.68,ink)
				ring(c,at,.12,gold)
			line(c,[Vector2(-.88,.82),Vector2(0,.95),Vector2(.88,.82)],gold)
		"wind_rose":
			star(c,4,.18,.92,ink,PI*.25)
			ring(c,Vector2.ZERO,.49,gold)
			for i: int in 4: petal(c,Vector2.from_angle(i*PI*.5)*.64,i*PI*.5+.7,.54,gold)
		"weave":
			for i: int in range(-3,4):
				var y: float = i*.22
				line(c,[Vector2(-.87,y-.12),Vector2(-.4,y+.12),Vector2(.2,y-.12),Vector2(.87,y+.12)],ink)
				line(c,[Vector2(y,-.87),Vector2(y+.12,0),Vector2(y,.87)],gold)
		"nectar_channels":
			for i: int in 3:
				var y: float = (i-1)*.46
				line(c,[Vector2(-.95,y),Vector2(-.35,y+.15),Vector2(.4,y-.1),Vector2(.95,y)],ink,.032)
				petal(c,Vector2(.56,y-.04),0,.30,gold)
		"queen_petals":
			for i: int in 4:
				var d := Vector2.from_angle(PI*.25+i*PI*.5)
				petal(c,d*.54,d.angle(),.83,ink)
			star(c,6,.15,.30,gold)
		"postal_tiles":
			line(c,[Vector2(-.85,-.50),Vector2(.85,-.50),Vector2(.85,.52),Vector2(-.85,.52),Vector2(-.85,-.50),Vector2(0,.13),Vector2(.85,-.50)],ink,.025)
			for x: float in [-.58,.58]: line(c,[Vector2(x,.82),Vector2(x+.22,.66)],gold,.03)
		"candy_wrappers":
			petal(c,Vector2.ZERO,0,1.0,ink)
			for side: float in [-1,1]:
				line(c,[Vector2(side*.48,0),Vector2(side*.92,-.38),Vector2(side*.78,0),Vector2(side*.92,.38),Vector2(side*.48,0)],gold,.03)
			for x: float in [-.25,0,.25]: line(c,[Vector2(x,-.19),Vector2(x+.14,.19)],gold)
		"chime_rosette":
			for i: int in 6:
				var d := Vector2.from_angle(i*TAU/6)
				petal(c,d*.50,d.angle(),.72,ink)
			ring(c,Vector2.ZERO,.25,gold,.03)
		"candle_lane":
			for i: int in 3:
				var x: float = (i-1)*.58
				line(c,[Vector2(x-.13,.60),Vector2(x-.13,-.25),Vector2(x+.13,-.25),Vector2(x+.13,.60)],ink,.024)
				petal(c,Vector2(x,-.56),-PI*.5,.42,gold)
			line(c,[Vector2(-.90,.68),Vector2(.90,.68)],gold,.032)
		"stitch_cross":
			for i: int in range(-3,4):
				var at := Vector2(i*.24,i*.24)
				line(c,[at+Vector2(-.08,.08),at+Vector2(.08,-.08)],ink,.04)
				at.y = -at.y
				line(c,[at+Vector2(-.08,-.08),at+Vector2(.08,.08)],gold,.04)
			ring(c,Vector2.ZERO,.30,ink)
			for at: Vector2 in [Vector2(-.1,-.1),Vector2(.1,-.1),Vector2(-.1,.1),Vector2(.1,.1)]: c.draw_circle(at,.035,gold)
		"moon_dock":
			c.draw_arc(Vector2(-.18,-.12),.65,PI*.20,PI*1.80,56,ink,.028,true)
			c.draw_arc(Vector2(.17,-.12),.44,PI*.27,PI*1.73,48,gold,.022,true)
			for y: float in [.63,.81]: line(c,[Vector2(-.80,y),Vector2(-.30,y-.05),Vector2(.3,y+.05),Vector2(.80,y)],ink)
		"patch_stage":
			star(c,5,.40,.86,ink)
			for i: int in 10:
				var d := Vector2.from_angle(i*TAU/10)
				line(c,[d*.90,d*.98],gold,.04)
			ring(c,Vector2.ZERO,.22,gold)
		"spiral_drum":
			var points := PackedVector2Array()
			for i: int in 129:
				var t: float = float(i)/128
				points.append(Vector2.from_angle(t*TAU*2.3)*(.08+t*.80))
			c.draw_polyline(points,ink,.035,true)
			ring(c,Vector2.ZERO,.96,gold)
		"market_rugs":
			for x: float in [-.48,.48]:
				line(c,[Vector2(x,-.86),Vector2(x+.38,0),Vector2(x,.86),Vector2(x-.38,0),Vector2(x,-.86)],ink,.022)
				line(c,[Vector2(x,-.42),Vector2(x+.18,0),Vector2(x,.42),Vector2(x-.18,0),Vector2(x,-.42)],gold,.024)
		"arena_net":
			ring(c,Vector2.ZERO,.90,ink,.027)
			ring(c,Vector2.ZERO,.71,gold)
			for i: int in range(-2,3):
				var v: float = i*.24
				var edge: float = sqrt(.65*.65-v*v)
				line(c,[Vector2(v,-edge),Vector2(v,edge)],ink,.012)
				line(c,[Vector2(-edge,v),Vector2(edge,v)],ink,.012)
		"forge_chevron":
			for y: float in [-.6,-.15,.3]: line(c,[Vector2(-.82,y),Vector2(0,y+.38),Vector2(.82,y)],ink,.042)
			for x: float in [-.44,.44]: petal(c,Vector2(x,.76),0,.40,gold)
		"beacon_rays":
			line(c,[Vector2(-.30,.62),Vector2(0,-.25),Vector2(.30,.62),Vector2(-.30,.62)],ink,.035)
			for i: int in 7:
				var a: float = -PI*.95+i*PI*.90/6
				line(c,[Vector2(0,-.3)+Vector2.from_angle(a)*.22,Vector2(0,-.3)+Vector2.from_angle(a)*.62],gold,.025)
			line(c,[Vector2(-.72,.88),Vector2(.72,.88)],gold,.026)
		"trial_triangles":
			for i: int in 3:
				var at := Vector2.from_angle(-PI*.5+i*TAU/3)*.40
				var points := PackedVector2Array()
				for j: int in 4: points.append(at+Vector2.from_angle(-PI*.5+j*TAU/3)*.43)
				c.draw_polyline(points,ink,.026,true)
			ring(c,Vector2.ZERO,.12,gold)
		"tusk_crown":
			line(c,[Vector2(-.8,-.6),Vector2(-.55,.45),Vector2(.55,.45),Vector2(.8,-.6),Vector2(.32,-.15),Vector2(0,-.83),Vector2(-.32,-.15),Vector2(-.8,-.6)],ink,.03)
			line(c,[Vector2(-.60,.65),Vector2(.60,.65)],gold,.04)
			star(c,6,.10,.24,gold)
