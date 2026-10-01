extends Node
## Captures the actual environment at opposite corners, covering all four edges.
const Fixed = preload("res://scripts/world/fixed_room_layouts.gd")
var failures := 0
var checks := 0

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("PERIMETER: "+label)

func frames(count: int = 3) -> void:
	for _index: int in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	if not Game.profile_path.contains("test_perimeter_visual"):
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280,720)
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","difficulty":0,"seed":146556}),"isolated expedition starts")
	var room: Node2D = load("res://scenes/room.tscn").instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	await frames()
	for id: String in ["L01","L07","L13","L19"]:
		var layout: Dictionary = Fixed.build(id)
		var prepared: Dictionary = room.prepare_expedition_node({"room_id":id,"role":"branch","biome_id":layout.biome_id,"node_index":1,"node_count":6,"difficulty":0,"seed":146556,"phase":"combat","expedition":true})
		check(bool(prepared.get("valid",false)),id+" production node prepares")
		if not bool(prepared.get("valid",false)): continue
		room.apply_prepared_expedition_node(prepared)
		var backdrop: Node2D = room.get_node("MineBackdrop")
		check(backdrop.environment_texture!=null and backdrop.environment_world_rect.has_area(),id+" production room installs a complete painted environment")
		print(str(layout.biome_id)+" plate world rect: "+str(backdrop.environment_world_rect))
		room.spawn_enabled = false
		for enemy: Node in room.enemies.get_children(): enemy.free()
		for sample: Dictionary in [{"label":"NW","at":Vector2(72,72)}, {"label":"SE","at":Vector2(2728,1728)}]:
			room.player.position = sample.at
			room.player.queue_redraw()
			room.camera.follow_target()
			room.camera.force_update_scroll()
			for body: Node in room.find_children("*","Node2D",true,false):
				if body.get_script()!=null and body.get_script().resource_path=="res://scripts/world/room_depth_sprite.gd": body._physics_process(.3)
			await frames(3)
			if DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				var frame: Image = get_viewport().get_texture().get_image()
				check(not frame.is_empty() and frame.save_png("res://artifacts/plate_"+str(layout.biome_id)+"_"+str(sample.label)+".png")==OK,id+" saves actual "+str(sample.label)+" boundary frame")
	room.free()
	await frames(2)
	print("Perimeter visual: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)
