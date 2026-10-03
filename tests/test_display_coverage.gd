extends Node
## Targeted render-bound regression. No combat simulation or real user saves.
const Backdrop = preload("res://scripts/combat/mine_backdrop.gd")
const Camera = preload("res://scripts/combat/world_camera.gd")
const Art = preload("res://scripts/world/world_art.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	if not Game.profile_path.contains("test_display_coverage"):
		get_tree().quit(2)
		return
	check(ProjectSettings.get_setting("display/window/stretch/aspect") == "expand", "expand avoids fixed-aspect letterboxing")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	add_child(viewport)
	var world := Node2D.new()
	viewport.add_child(world)
	var player := Node2D.new()
	world.add_child(player)
	var backdrop := Backdrop.new()
	world.add_child(backdrop)
	var arena := Rect2(0,0,1624,1044)
	backdrop.configure(arena,"B05",41827,"service_entrance")
	check(backdrop.environment_texture == null, "service fixture reaches missing-environment fallback")
	check(backdrop.floor_texture != null, "fallback floor texture loads")
	check(backdrop.painted_bounds() == arena.grow(200), "fallback ground covers camera scenery margin")
	var camera := Camera.new()
	camera.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(camera)
	camera.configure(world,player,arena,backdrop.painted_bounds())
	for extent: Vector2i in [Vector2i(1280,720),Vector2i(1280,960),Vector2i(1280,800),Vector2i(1920,720),Vector2i(1280,1280),Vector2i(1280,720)]:
		viewport.size=extent
		await get_tree().process_frame
		camera._fit_render_frame()
		check(is_equal_approx(camera.zoom.x,camera.zoom.y),"uniform world scaling at "+str(extent))
		for point: Vector2 in [arena.position,arena.get_center(),arena.end,Vector2(arena.position.x,arena.end.y),Vector2(arena.end.x,arena.position.y)]:
			player.position=point
			camera.follow_target()
			camera.force_update_scroll()
			await get_tree().process_frame
			var visible:=Rect2(camera.get_screen_center_position()-Vector2(extent)/camera.zoom*.5,Vector2(extent)/camera.zoom)
			check(backdrop.painted_bounds().grow(1.1).encloses(visible),"painted fallback covers viewport "+str(extent)+" at "+str(point))
	check(backdrop.arena==arena,"coverage never changes gameplay arena")
	# Route previews must use the room-specific registry, not retired faction art.
	for id: String in ["L01","L06","BO01","L26","L30","BO05"]:
		var biome: String="B05" if id in ["L26","L30","BO05"] else "B01"
		check(Art.environment_texture_for(biome,id)!=null,"route preview exists for "+id)
	backdrop.configure(arena,"B01",41827,"L01")
	check(backdrop.painted_bounds()==Art.environment_world_rect(arena,"B01","L01"),"authored full painting keeps its original coverage")
	print("DISPLAY_COVERAGE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
