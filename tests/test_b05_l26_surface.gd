extends Node
const Layouts=preload("res://scripts/world/b05_room_layouts.gd")
const Geometry=preload("res://scripts/world/b05_room_geometry.gd")
const Repair=preload("res://scripts/world/b05_floor_repair.gd")
var checks:=0
var failures:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1;push_error("L26 SURFACE: "+label)
func _ready() -> void: _run.call_deferred()
func capture(viewport: SubViewport) -> Image:
	await get_tree().process_frame;await get_tree().process_frame
	RenderingServer.force_draw(false)
	return viewport.get_texture().get_image()
func _run() -> void:
	var output:=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output.is_empty() or not Game.profile_path.contains("test_b05_l26_surface"): get_tree().quit(2);return
	var layout:=Layouts.build("L26",26001)
	var frozen:=Geometry.polygon("L26")
	var closed:=Repair.new();add_child(closed)
	check(not closed.configure(layout,false),"candidate requires opt-in")
	closed.free()
	var backdrop=preload("res://scripts/combat/mine_backdrop.gd").new();add_child(backdrop)
	backdrop.configure(layout.arena,"B05",26001,"L26")
	backdrop.configure_layout(layout)
	check(not is_instance_valid(backdrop.b05_floor_repair),"production gate stays closed")
	backdrop.configure_layout(layout,true)
	check(is_instance_valid(backdrop.b05_floor_repair) and backdrop.b05_floor_repair.z_index==1,"real backdrop opt-in layers above painting")
	backdrop.configure_layout(layout)
	check(not is_instance_valid(backdrop.b05_floor_repair),"repeat configure removes old candidate")
	backdrop.free()
	var viewport:=SubViewport.new();viewport.size=Vector2i(1536,1024)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var base:=Sprite2D.new();base.centered=false;base.z_index=-10
	base.texture=load("res://assets/generated/world/rooms/L26_environment_v1.png")
	viewport.add_child(base)
	var repair:=Repair.new();viewport.add_child(repair)
	check(repair.configure(layout,true),"native repair+fascia configure")
	check(repair.layers.size()==2,"separate native texture layers")
	var ratio:=Vector2(1536,1024)/repair.world_rect.size
	repair.scale=ratio;repair.position=-repair.world_rect.position*ratio
	check(Geometry.polygon("L26")==frozen,"frozen collision unchanged")
	check(Geometry.route_is_clear("L26","main_route",180) and Geometry.route_is_clear("L26","safe_route",140),"frozen main and safe route widths")
	check(repair.layers[0].texture.get_size()==Vector2(1254,1254),"floor uses native1254 texture")
	check(repair.layers[1].texture.get_size()==Vector2(1536,1024),"fascia uses native1536x1024")
	if DisplayServer.get_name()=="headless":
		print("B05_L26_SURFACE structural checks=",checks," failures=",failures," graphical=NOT_RUN")
		get_tree().quit(1 if failures else 0);return
	repair.visible=false
	var before: Image=await capture(viewport)
	repair.visible=true
	var after: Image=await capture(viewport)
	check(after.get_size()==Vector2i(1536,1024),"actual1536x1024 render")
	check(before.save_png(output.path_join("L26_before.png"))==OK and after.save_png(output.path_join("L26_after.png"))==OK,"two scoped comparison frames saved")
	check(before.get_pixel(768,300)==after.get_pixel(768,300),"northern source unchanged")
	check(before.get_pixel(768,900)==after.get_pixel(768,900),"south portal painting unchanged")
	check(before.get_pixel(480,810)!=after.get_pixel(480,810),"southern missing floor filled")
	check(before.get_pixel(480,838)!=after.get_pixel(480,838),"fascia contacts frozen southern edge")
	print("B05_L26_SURFACE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
