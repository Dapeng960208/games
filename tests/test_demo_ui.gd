extends Node

var app: Node
var viewport: SubViewport
var checks := 0
var failures := 0

func _ready() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func frames(count: int = 3) -> void:
	for frame in count:
		await get_tree().process_frame
		await get_tree().physics_frame

func capture(suffix: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	viewport.get_texture().get_image().save_png("res://artifacts/demo_ui_"+suffix+".png")

func run_checks() -> void:
	if not Game.profile_path.contains("test_demo_ui"):
		get_tree().quit(2)
		return
	check(Game.new_profile(),"isolated demo UI profile created")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	app = load("res://scenes/main.tscn").instantiate()
	viewport.add_child(app)
	await frames()
	await capture("menu_final")
	check(app.screen.find_child("FullSkillDemo",true,false) != null,"menu has a direct full-skill trial entry")
	check(is_instance_valid(app.music),"one persistent music director exists")
	app.show_camp()
	await frames()
	await capture("camp_final")
	check(app.route == "camp","production camp renders")
	app.show_workshop("inventory")
	await frames()
	await capture("equipment_final")
	for pair: Array in [["move_up",KEY_UP],["move_down",KEY_DOWN],["move_left",KEY_LEFT],["move_right",KEY_RIGHT],["circuit_place",KEY_C],["circuit_release",KEY_V]]:
		var event := InputEventKey.new()
		event.physical_keycode = pair[1]
		check(InputMap.action_has_event(pair[0],event),str(pair[0])+" physical input is mapped")
	app.show_demo_select()
	await frames()
	await capture("heroes_final")
	for hero: String in ["CH01","CH02","CH03"]:
		check(app.screen.find_child("Demo_"+hero,true,false) != null,hero+" has an explicit trial button")
	app._start_demo("CH01")
	await frames()
	check(Game.run != null and Game.run.demo and Game.run.level == 8,"trial button starts isolated level-eight expedition")
	check(app.route == "run" and get_tree().paused,"first-run brief pauses production combat")
	await capture("brief_final")
	app._pop_modal()
	app.room.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	check(not get_tree().paused,"brief closes and releases the gameplay pause")
	check(app.hud.skill_slots[1].key == "鼠标右键","secondary skill spells out the full mouse button")
	check(app.hud.skill_slots[4].key == "空格","dash spells out the space key")
	for slot: Button in app.hud.skill_slots:
		check(not bool(slot.state.get("locked",true)),slot.name+" is available in the trial")
	check(app.hud.circuit_panel.visible,"real circuit state is visible in the HUD")
	check(not app.hud.class_label.text.is_empty(),"real class mechanic state is visible in the HUD")
	var coverage := 0.0
	for rect: Rect2 in app.hud.coverage_rects(): coverage += rect.get_area()
	check(coverage/(1280.0*720.0) < 0.15,"standing HUD stays below fifteen percent of the game area")
	await capture("combat_final")
	app._show_expedition_relic({"offer_id":"visual_fixture","candidates":["RL01","RL02","RL03"]})
	await frames()
	await capture("relics_final")
	check(app.modals[-1].node.find_child("RelicChoice_RL01",true,false) != null,"production relic decision renders three choices")
	var artwork: TextureRect = app.modals[-1].node.find_child("RelicArtwork",true,false)
	check(artwork != null and artwork.texture != null,"class relic cards load their original artwork resource")
	check(artwork != null and artwork.size == Vector2(88,88),"relic artwork stays inside its 88-pixel display bounds")
	app._clear_modals()
	app.show_combat_details("secondary")
	await frames()
	check(get_tree().paused,"combat details pauses safely")
	app.show_attributes()
	await frames()
	check(app.modals[-1].node.find_child("Attribute_attack",true,false) != null,"attribute view reads actual resolved attack")
	check(app.modals[-1].node.find_child("Attribute_magic_resist",true,false) != null,"attribute view exposes magic resistance")
	var dossier: Control = app.modals[-1].node.find_child("CharacterDossier",true,false)
	check(dossier.find_children("Equipment_*","Button",true,false).size() == 6,"game character dossier shows all six equipped slots")
	var attack_row: Button = dossier.find_child("AttributeRow_attack",true,false)
	attack_row.focus_entered.emit()
	check(dossier.detail_body.text.contains("基础") and dossier.detail_body.text.contains("装备"),"stat focus explains base and equipment contributions")
	await capture("attributes_final")
	app._pop_modal()
	app._pop_modal()
	for effect: String in ["bleed","grievous","damage_reduction","invulnerable"]:
		app.room.player.status.apply(effect,0.12,2.5)
	app.hud.refresh()
	for effect: String in ["bleed","grievous","damage_reduction","invulnerable"]:
		check(app.hud.buff_chips.has(effect) and app.hud.buff_chips[effect].remaining_seconds() == 3,effect+" HUD chip follows the actual combat status timer")
	app.room.player.status.states.clear()
	app.hud.refresh()
	check(not app.hud.buff_chips.has("invulnerable"),"expired combat status indicators are removed")
	app.show_settings()
	await frames()
	check(app.audio_sliders.size() == 3,"settings provides master/music/SFX sliders")
	app.audio_sliders.music_volume.value = 0.23
	app._pop_modal()
	check(is_equal_approx(float(Game.profile.settings.music_volume),0.23),"closing settings immediately commits its volume value")
	check(not get_tree().paused,"settings preserves the modal pause lifecycle")
	Game.finish_run("abandoned")
	await frames()
	check(app.route == "result" and Game.run == null,"trial settlement reaches the production result screen")
	check(is_equal_approx(float(Game.profile.settings.music_volume),0.55),"trial settings restore the original profile")
	app.free()
	await frames()
	print("DEMO UI: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)
