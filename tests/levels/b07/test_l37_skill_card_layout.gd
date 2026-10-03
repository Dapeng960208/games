extends SceneTree
## Pure screen geometry checks: no game scene, assets generated or graphics.
const Layout = preload("res://scripts/levels/b07/art/l37_skill_card_layout.gd")
func _initialize() -> void:
	var viewport := Rect2(8,8,1264,704)
	var native := Rect2(500,320,254,61)
	var bodies: Array[Rect2] = [Rect2(460,240,300,220)]
	var occupied: Array[Rect2] = []
	var first := Layout.choose(native,viewport,bodies,occupied)
	assert(viewport.encloses(first.rect))
	assert(not first.fallback)
	assert(not Rect2(first.rect).intersects(bodies[0].grow(Layout.GAP)))
	occupied.append(first.rect)
	var second := Layout.choose(native,viewport,bodies,occupied)
	assert(viewport.encloses(second.rect))
	assert(not Rect2(second.rect).intersects(Rect2(first.rect).grow(Layout.GAP)))
	assert(not Rect2(second.rect).intersects(bodies[0].grow(Layout.GAP)))
	var full: Array[Rect2] = [viewport]
	var fallback := Layout.choose(native,viewport,full,occupied)
	assert(fallback.fallback and fallback.perimeter and fallback.overlap_score>0)
	assert(viewport.encloses(fallback.rect))
	var small := Layout.choose(native,Rect2(0,0,100,30),full,occupied)
	assert(not small.fits_viewport)
	# Exercise the actual screen-to-local mapping with scaled camera matrices.
	# Translation must not be included in a displacement vector's inverse.
	for scale_value: Vector2 in [Vector2(.72,.72),Vector2(1.44,1.44),Vector2(.72,1.15)]:
		var matrix := Transform2D(0.0,scale_value,0.0,Vector2(415,207))
		var origin := Vector2(21,-29)
		var before: Rect2 = matrix*Rect2(origin,Layout.SIZE)
		var offset := Vector2(-187,93)
		var local := Layout.displaced_origin(matrix,origin,offset)
		var actual: Rect2 = matrix*Rect2(local,Layout.SIZE)
		assert(actual.position.is_equal_approx(before.position+offset))
		assert(actual.size.is_equal_approx(before.size))
	assert(Layout.placement(null).is_empty())
	var actor := Node2D.new()
	var badge := Node2D.new()
	actor.add_child(badge)
	assert(Layout.placement(badge).is_empty())
	actor.free()
	print("L37 CARD LAYOUT: pure geometry checks passed; live visual acceptance pending")
	quit()
