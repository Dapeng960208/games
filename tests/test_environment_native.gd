extends "res://tests/test_environment_clarity.gd"
## Graphical native-room acceptance using only production assets/manifests.
## tools/test.ps1 -Suite environment_native -Graphical
## Optional --native-room=L01 selects another available pack.
const NATIVE_OUTPUT := "res://artifacts/environment-native/"
var room_under_test := "L16"
func native_capture(label: String) -> void:
 var pixels: Image = await capture_pixels()
 check(pixels.get_size()==Vector2i(2560,1440),"native-room actual framebuffer is 2560x1440")
 check(pixels.save_png(NATIVE_OUTPUT+label+".png")==OK,"native-room capture saved")
func attach_native_tiles() -> Node2D:
 var backdrop=room.get_node("MineBackdrop")
 if is_instance_valid(backdrop.environment_chunks.native_detail): return backdrop.environment_chunks.native_detail
 var detail=preload("res://scripts/world/environment_detail.gd").new()
 check(detail.configure(room_under_test,backdrop.environment_world_rect,true),"candidate full native pack loads")
 backdrop.environment_chunks.add_child(detail)
 return detail
func _run() -> void:
 for argument: String in OS.get_cmdline_user_args():
  if argument.begins_with("--native-room="): room_under_test=argument.trim_prefix("--native-room=")
 if not Game.profile_path.contains("test_environment_native") or DisplayServer.get_name()=="headless":
  push_error("Native room acceptance requires an isolated test_environment_native profile and graphical rendering")
  get_tree().quit(2)
  return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NATIVE_OUTPUT))
 # Only after the isolated-path guard: discard a previous test run restored
 # from this fixture profile, never from the actual player profile.
 Game.run=null
 var started=Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":146556})
 check(started,"isolated native-room run starts")
 if not started:
  get_tree().quit(1)
  return
 Words.set_locale("zh_CN")
 room=load("res://scenes/room.tscn").instantiate()
 room.spawn_enabled=false
 room.process_mode=Node.PROCESS_MODE_DISABLED
 add_child(room)
 layer=CanvasLayer.new()
 add_child(layer)
 hud=load("res://scenes/hud.tscn").instantiate()
 hud.room=room
 layer.add_child(hud)
 hud.set_process(false)
 get_window().content_scale_size=Vector2i(1280,720)
 get_window().size=Vector2i(2560,1440)
 await frames()
 if not await install(room_under_test): return
 var geometry_before=var_to_str(room.layout)
 var ground_before=room.ground_polygon.duplicate()
 var camera_before=room.camera.zoom
 var native=attach_native_tiles()
 var texture_weakrefs: Array=[]
 for tile: Sprite2D in native.tiles: texture_weakrefs.append(weakref(tile.texture))
 print("NATIVE_ROOM_RESIDENCY native_rgba_mips_upper_bound=",native.resident_bytes," gpu_texture_memory=",Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
 var views={"center":Vector2(.5,.5),"northwest":Vector2(.2,.2),"northeast":Vector2(.8,.2),"southwest":Vector2(.2,.8),"southeast":Vector2(.8,.8)}
 for label: String in views:
  room.player.position=room.clamp_actor(Art.environment_point(room.layout.arena,str(room.layout.biome_id),views[label],room_under_test),30)
  room.camera.follow_target()
  room.camera.force_update_scroll()
  hud.visible=label=="center"
  await frames()
  native.hide()
  await native_capture(room_under_test+"_"+label+"_original_2560x1440")
  native.show()
  await native_capture(room_under_test+"_"+label+"_native_2560x1440")
 check(geometry_before==var_to_str(room.layout) and ground_before==room.ground_polygon and camera_before==room.camera.zoom,"tile art preserves exact layout, walkable polygon and camera")
 native.clear()
 await frames()
 for reference: WeakRef in texture_weakrefs: check(reference.get_ref()==null,"native texture freed when room pack cleared")
 print("NATIVE_ROOM_RESIDENCY after_clear_gpu_texture_memory=",Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
 native.free()
 for id: String in ["L17","L18",room_under_test]:
  check(await install(id),"room transition "+id)
  check(Art._environments.size()<=Art.ENVIRONMENT_CACHE_LIMIT,"original environment cache bounded to2")
  if id==room_under_test:
   var reload=attach_native_tiles()
   check(reload.tiles.size()==6,"six native tiles reload after room transition")
   print("NATIVE_ROOM_RESIDENCY reloaded_rgba_mips=",reload.resident_bytes," gpu_texture_memory=",Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
   reload.free()
 check(await room.combat_audio.wait_for_cleanup(),"native-room audio drains")
 layer.free()
 room.free()
 Game.run=null
 print("ENVIRONMENT_NATIVE_RESULT checks=",checks," failures=",failures," full_visual_review_pending=true")
 get_tree().quit(1 if failures else 0)
