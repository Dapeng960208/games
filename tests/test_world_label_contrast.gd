extends "res://tests/test_room_presentation.gd"
## Focused production-label regression; optional GPU evidence is native 2K.
## tools/test.ps1 -Suite world_label_contrast -SkipImport [-Graphical]
const Labels = preload("res://scripts/ui/world_label_layer.gd")
const LABEL_OUTPUT := "res://artifacts/world-label-contrast/"
var graphical := false

func luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return linear.r * .2126 + linear.g * .7152 + linear.b * .0722

func contrast(ink: Color, paper: Color) -> float:
	return (luminance(paper) + .05) / (luminance(ink) + .05)

func value_state(value: Variant) -> Variant:
	# Objective dictionaries reference live Nodes; serializing those recursively
	# walks the whole room and its callbacks instead of its value-only state.
	if value is Object: return value.get_instance_id() if is_instance_valid(value) else 0
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[key] = value_state(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(value_state(item))
		return result
	return value

func room_state() -> String:
	return var_to_str(value_state([room.layout,room.ground_polygon,room.obstructions,room.objectives.elements,room.enemy_props.props,room.camera.zoom,room.player.position]))

func label_layer_checks(host: Node2D, label: String) -> void:
	var text_layer: Node2D = host.label_layer
	check(is_instance_valid(text_layer) and text_layer.get_parent() == host, label + " owns its text layer")
	if not is_instance_valid(text_layer): return
	check(host.material is ShaderMaterial and text_layer.material is CanvasItemMaterial and not text_layer.use_parent_material, label + " text bypasses the artwork shader")
	check(text_layer.material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED, label + " text keeps authored colors")
	check(text_layer.transform == Transform2D.IDENTITY and text_layer.z_index == 0 and text_layer.z_as_relative, label + " preserves world positions and host depth")
	check(text_layer.painter.is_valid() and host.draw.is_connected(text_layer.queue_redraw), label + " redraws with its host without an independent tick")
	check(not text_layer.is_processing() and not text_layer.is_physics_processing(), label + " has no gameplay processing")

func actual_ink_checks(pixels: Image, text_layer: Node2D, font: Font, text: String, baseline: Vector2, size_px: int, ink: Color, label: String) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var logical := Rect2(baseline - Vector2(width * .5, font.get_ascent(size_px)), Vector2(width, font.get_height(size_px)))
	var transform := text_layer.get_global_transform_with_canvas()
	var scale := Vector2(pixels.get_size()) / get_viewport().get_visible_rect().size
	var screen := Rect2i(Rect2((transform * logical.position) * scale, logical.size * transform.get_scale() * scale))
	screen = screen.intersection(Rect2i(Vector2i.ZERO, pixels.get_size()))
	var matching := 0
	for y: int in range(screen.position.y, screen.end.y):
		for x: int in range(screen.position.x, screen.end.x):
			var color := pixels.get_pixel(x, y)
			if absf(color.r - ink.r) < .045 and absf(color.g - ink.g) < .045 and absf(color.b - ink.b) < .045:
				matching += 1
	check(matching >= text.length() * 2, label + " contains actual high-contrast glyph pixels: " + str(matching))

func capture_labels(label: String) -> void:
	if not graphical: return
	room.objectives.queue_redraw()
	room.enemy_props.queue_redraw()
	await frames(3)
	RenderingServer.force_draw(false)
	var pixels: Image = get_viewport().get_texture().get_image()
	check(pixels.get_size() == Vector2i(2560,1440), label + " actual framebuffer is native 2560x1440")
	check(pixels.save_png(LABEL_OUTPUT + label + ".png") == OK, label + " screenshot saved")
	for item: Dictionary in room.objectives.elements.values():
		if not bool(item.get("active",true)) or bool(item.get("carried",false)) or bool(item.get("destroyed",false)):
			continue
		if not room.objectives.near(item.position,260) and not bool(item.get("always_label",false)):
			continue
		var text := str(item.label) + (" ✓" if bool(item.get("done",false)) else "")
		if not str(item.get("phase","")).is_empty(): text += " · " + str(item.phase)
		actual_ink_checks(pixels,room.objectives.label_layer,room.objectives.objective_font,text,item.position+Vector2(0,44),17,Labels.INK,label+" objective")
	for item: Dictionary in room.enemy_props.props:
		if room.player.position.distance_to(item.position) > 160 or not room.enemy_props._line_clear(room.player.position,item.position): continue
		var english: bool = str(Game.profile.settings.language) == "en"
		var title := str(item.name_en if english else item.name)
		var detail := str(item.description_en if english else item.description)
		if bool(item.used):
			title = ("Recharging · %ds" if english else "信标休眠 · %d秒") % ceili(float(item.cooldown))
			detail = "New function at this spot" if english else "原位刷新 · 功能随机"
		elif not bool(item.armed): detail = "Leave the ring, then approach" if english else "离开光环后再次靠近"
		else: detail += " · Approach" if english else " · 靠近生效"
		actual_ink_checks(pixels,room.enemy_props.label_layer,room.enemy_props._font,title,item.position+Vector2(0,49),15,Labels.DETAIL if bool(item.used) else Labels.INK,label+" beacon title")
		actual_ink_checks(pixels,room.enemy_props.label_layer,room.enemy_props._font,detail,item.position+Vector2(0,67),13,Labels.DETAIL,label+" beacon detail")

func _run() -> void:
	if not Game.profile_path.contains("test_world_label_contrast"):
		push_error("World-label checks require an isolated test_world_label_contrast profile")
		get_tree().quit(2)
		return
	graphical = DisplayServer.get_name() != "headless"
	check(contrast(Labels.INK,Labels.PAPER) >= 7.0,"primary text exceeds 7:1 on its opaque ivory backing")
	check(contrast(Labels.DETAIL,Labels.PAPER) >= 4.5,"beacon detail and cooldown text exceed 4.5:1")
	check(Labels.PAPER.a == 1.0,"floor texture cannot dilute text contrast")
	var font := Labels.font()
	var weight := TextServerManager.get_primary_interface().name_to_tag("wght")
	check(font is FontVariation and float(font.variation_opentype.get(weight,0)) == 500.0,"world labels match the HUD medium weight rather than the source font's hairline default")
	Game.run = null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":146556}),"isolated production run starts")
	Words.set_locale("zh_CN")
	room = load("res://scenes/room.tscn").instantiate()
	room.spawn_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	layer = CanvasLayer.new()
	add_child(layer)
	hud = load("res://scenes/hud.tscn").instantiate()
	hud.room = room
	layer.add_child(hud)
	hud.set_process(false)
	if graphical:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LABEL_OUTPUT))
		get_window().content_scale_size = Vector2i(1280,720)
		get_window().size = Vector2i(2560,1440)
	await frames()
	for id: String in ["L06","L10"]:
		if not await install(id): continue
		label_layer_checks(room.objectives,id+" objective")
		label_layer_checks(room.enemy_props,id+" beacon")
		room.player.position = room.clamp_actor(Art.environment_point(room.layout.arena,str(room.layout.biome_id),Vector2(.5,.5),id),30)
		room.camera.follow_target()
		room.camera.force_update_scroll()
		hud.refresh()
		for item: Dictionary in room.objectives.elements.values():
			print("WORLD_LABEL_VISIBILITY room=",id," label=",item.label," distance=",room.player.position.distance_to(item.position)," visible=",room.objectives.near(item.position,260) or bool(item.get("always_label",false)))
		var before := room_state()
		await capture_labels(id+"_center_zh_2560x1440")
		check(before == room_state(),id+" rendering preserves layout, collision, state and camera")
	# Additional text states use one real beacon and its exact original anchor.
	var beacon: Dictionary = room.enemy_props.props[1]
	var saved_beacon := beacon.duplicate(true)
	room.player.position = beacon.position
	room.camera.follow_target()
	room.camera.force_update_scroll()
	for locale: String in ["zh_CN","en"]:
		Game.profile.settings.language = locale
		Words.set_locale(locale)
		hud.refresh()
		for state: String in ["ready","reapproach","cooldown"]:
			beacon.used = state == "cooldown"
			beacon.armed = state == "ready"
			beacon.cooldown = 17.25 if bool(beacon.used) else 0.0
			var before := var_to_str(beacon)
			await capture_labels("L10_beacon_"+locale+"_"+state+"_2560x1440")
			check(before == var_to_str(beacon),locale+" "+state+" label does not consume or change the beacon")
	beacon.merge(saved_beacon,true)
	var old_objective_layer: WeakRef = weakref(room.objectives.label_layer)
	var old_beacon_layer: WeakRef = weakref(room.enemy_props.label_layer)
	check(await room.combat_audio.wait_for_cleanup(),"label fixture audio drains")
	layer.free()
	room.free()
	Game.run = null
	await frames(2)
	check(old_objective_layer.get_ref() == null and old_beacon_layer.get_ref() == null,"text layers are freed with their room hosts")
	print("WORLD_LABEL_CONTRAST_RESULT checks=",checks," failures=",failures," graphical=",graphical," primary_ratio=",contrast(Labels.INK,Labels.PAPER)," detail_ratio=",contrast(Labels.DETAIL,Labels.PAPER))
	get_tree().quit(1 if failures else 0)
