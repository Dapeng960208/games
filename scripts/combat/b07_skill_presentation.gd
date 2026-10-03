extends RefCounted
## Essential B07 tells are independent of optional path/particle settings.
## Procedural mound/shadow are honest runtime markers, not completed actor art.
static func draw_warning(canvas: Node2D, actor: Node2D, command: Dictionary) -> void:
	if str(command.get("kind",""))=="b07_heal":
		var points:=PackedVector2Array([actor.position])
		for ref: WeakRef in command.get("b07_target_refs",[]):
			var ally: Node2D=ref.get_ref()
			if is_instance_valid(ally): points.append(ally.position)
		if points.size()>1:
			canvas.draw_polyline(points,Color("172e2d"),6,true)
			canvas.draw_polyline(points,Color("77ddbd"),3,true)
			for point: Vector2 in points: canvas.draw_circle(point,5,Color("d0ffdb"))
	elif bool(command.get("b07_mound",false)):
		draw_mound(canvas,actor.position,Vector2(command.target),float(command.radius))

static func draw_mound(canvas: Node2D, at: Vector2, destination: Vector2, radius: float) -> void:
	canvas.draw_circle(at+Vector2(0,5),23,Color(.07,.05,.025,.8))
	var mound:=PackedVector2Array([at+Vector2(-23,3),at+Vector2(-12,-8),at+Vector2(0,-14),at+Vector2(13,-8),at+Vector2(23,3)])
	canvas.draw_colored_polygon(mound,Color("bc8a42"))
	canvas.draw_polyline(mound,Color("f6d796"),2,true)
	canvas.draw_circle(destination,15,Color(.1,.075,.04,.75))
	canvas.draw_arc(destination,radius,0,TAU,40,Color("ffbc67"),2.5,true)
