extends SceneTree
const Layouts=preload("res://scripts/levels/b05/world/room_layouts.gd")
const Geometry=preload("res://scripts/levels/b05/world/room_geometry.gd")
const Art=preload("res://scripts/infrastructure/assets/world_art.gd")
const Backdrop=preload("res://scripts/gameplay/world/environment_backdrop.gd")
var checks:=0
var failures:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1;push_error("B05 MAP: "+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for id: String in ["L25","L26","L27","L28","L29","L30","BO05"]:
		var layout:=Layouts.build(id,251007)
		var frozen:=Geometry.polygon(id)
		var definition:=Art.environment_definition("B05",id)
		check(not definition.is_empty() and bool(definition.get("room_specific",false)),id+" real room-specific native source")
		check(definition.texture.get_size()==Vector2(1536,1024),id+" fullbase dimensions explicit")
		var backdrop:=Backdrop.new();root.add_child(backdrop)
		backdrop.configure(layout.arena,"B05",251007,id)
		backdrop.configure_layout(layout,false)
		check(not is_instance_valid(backdrop.environment_chunks.native_detail),id+" unapproved nativepack stays gated")
		backdrop.configure_layout(layout,true)
		var manifest:="asset://world/rooms_2k/"+id+"/manifest.json"
		if FileAccess.file_exists(AssetCatalog.resolve(manifest)):
			check(is_instance_valid(backdrop.environment_chunks.native_detail) and backdrop.environment_chunks.native_detail.tiles.size()==6,id+" candidate sixpack loads")
		if id=="L27":
			check(is_instance_valid(backdrop.b05_fixed_void),"L27 separate nativevoid loads")
			var values: Array=Geometry.room(id).voids[0]
			check(backdrop.b05_fixed_void.world_rect.is_equal_approx(Rect2(Geometry.world_point([values[0],values[1]]),Geometry.world_point([values[2],values[3]]))),"void visual exactly matches frozen collision rectangle")
		if id in ["L26","L27","L29","L30","BO05"]:
			var patch_manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve("asset://world/rooms_2k/"+id+"/native_floor_patches_v1.json")))
			check(not patch_manifest.approved,id+" repairs remain candidates")
			var repairs=backdrop.b05_floor_repair
			check(repairs.layers.size()==patch_manifest.patches.size()+1,id+" unique floor patches plus fascia")
			if id=="L30":check(not repairs.layers[-1].visible,"L30 retains native perimeter without a partial false fascia")
			if id=="L29":check(not repairs.layers[-1].material.get_shader_parameter("fascia_all_edges"),"L29 south trim excludes artificial upright side stubs")
			if id=="L27":check(repairs.layers[0].material.get_shader_parameter("entrance_join_rect")==Vector4(220.306285056,435,48,145),"L27 local flat entry blend remains bounded")
			for i in patch_manifest.patches.size():
				var patch: Dictionary=patch_manifest.patches[i]
				check(FileAccess.get_sha256(patch.texture)==patch.sha256,id+" exact generated repair bytes")
				check(repairs.layers[i].texture.get_size()==Vector2(patch.native_size[0],patch.native_size[1]),id+" exact native patch dimensions")
				var mapping: Array=patch.recommended_repair_source_rect
				check(repairs.layers[i].material.get_shader_parameter("repair_rect")==Vector4(mapping[0],mapping[1],mapping[2],mapping[3]),id+" unique patch mapping preserves source crop")
				var clip: Array=patch.get("paint_clip_source_rect",mapping)
				check(repairs.layers[i].material.get_shader_parameter("paint_clip_rect")==Vector4(clip[0],clip[1],clip[2],clip[3]),id+" bounded paint independent of source UV")
				check(repairs.layers[i].material.get_shader_parameter("unique_patch"),id+" unique UV without periodic repetition")
				check(not repairs.layers[i].material.get_shader_parameter("match_reference_shading"),id+" native shadows without tint reconstruction")
		check(Geometry.polygon(id)==frozen,id+" frozen ground unchanged")
		backdrop.free()
		await process_frame
	print("B05_MAP_REGISTRATION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
