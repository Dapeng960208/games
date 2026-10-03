extends Node

const Readout = preload("res://scripts/presentation/hud/progression_readout.gd")
var viewport: SubViewport
var app: Node
var checks := 0
var failures := 0

func _ready() -> void:
	call_deferred("run_checks")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("Growth feedback: "+text)

func frames(count: int = 3) -> void:
	for index in count:
		await get_tree().process_frame
		await get_tree().physics_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	viewport.get_texture().get_image().save_png("res://artifacts/growth_"+name+".png")

func run_checks() -> void:
	if not Game.profile_path.contains("test_growth_feedback"):
		get_tree().quit(2)
		return
	# Core expedition commits are covered by first_run_progression. Here use the
	# real immediate XP API to isolate UI reaction, queueing and modal lifecycle.
	check(Game.new_profile(),"isolated save")
	check(Game.select_hero("CH03"),"select node hero")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	viewport.add_child(app)
	await frames()
	check(Game.start_run(),"production run and HUD created")
	await frames()
	app.room.process_mode = Node.PROCESS_MODE_DISABLED
	check(app.hud.experience_label.text == "0/30 XP","fresh XP starts at actual level floor")
	check(not app.hud.skill_slots[0].state.locked and app.hud.skill_slots[1].state.locked,"first Q is usable while node is locked")
	check(app.hud.notifications.is_empty() and app.hud.toast_remaining == 0.0,"loading a run creates no fake level-up")
	check(Readout.next_goal("CH03",0).contains("鼠标右键") and Readout.next_goal("CH03",0).contains("30"),"next goal names skill, key and real distance")
	await capture("level1")
	check(Game.grant_hero_xp(30,"ui:first_room"),"real committed XP unlocks node")
	await frames()
	check(Game.run.level == 2 and app.hud.experience_label.text == "0/40 XP","new XP span resets at level boundary")
	check(app.hud.toast.text.contains("共鸣节点") and app.hud.toast.text.contains("Q"),"unlock receipt tells player the skill and its combo")
	check(app.hud.skill_slots[1].unlock_flash > 0.0,"newly available slot receives visual emphasis")
	await capture("node_unlocked")
	var held_time: float = app.hud.toast_remaining
	app.show_pause()
	await frames(12)
	check(get_tree().paused and is_equal_approx(app.hud.toast_remaining,held_time),"modal pauses unlock notification lifetime")
	check(not app.hud.toast.visible,"notification stays hidden under modal")
	app._clear_modals()
	await frames()
	check(app.hud.toast.visible,"notification continues after modal closes")
	# Two events in one frame must both reach the player, not overwrite each other.
	check(Game.grant_hero_xp(40,"ui:second_room"),"F unlocked by real XP")
	check(Game.equip_relic("split"),"same-frame relic receipt")
	app.hud.refresh()
	check(app.hud.notifications.size() == 2,"unlock and relic notifications queue independently")
	app.hud.toast_remaining = 0
	await frames()
	check(app.hud.toast.text.contains("共振引爆") and app.hud.toast.text.contains("先布节点"),"F notice explains node charge detonation")
	await capture("detonation_unlocked")
	app.hud.toast_remaining = 0
	await frames()
	check(app.hud.toast.text.contains("共鸣棱镜"),"queued class relic is still shown")
	app.hud.notifications.clear()
	app.hud.toast_remaining = 0
	var stored_xp: int = Game.profile.hero_xp.CH03
	Game.run.staged_tutorial = true
	app.hud.refresh()
	check(Game.profile.hero_xp.CH03 == stored_xp and Game.run.level == 3,"pending tutorial never advances committed progression")
	app.hud.progression_button.mouse_entered.emit()
	app.hud._update_tooltip()
	check(app.hud.tooltip_body.text.contains("待结算：30") and app.hud.tooltip_body.text.contains("穹顶共振"),"growth tooltip distinguishes pending XP and next skill")
	app.hud.progression_button.pressed.emit()
	await frames()
	check(app.modals[-1].node.find_child("CharacterDossier",true,false) != null,"clicking growth opens actual character equipment panel")
	app._clear_modals()
	Game.run.staged_tutorial = false
	check(Game.grant_hero_xp(3530,"ui:max_level"),"max-level boundary uses production XP cap")
	app.hud.refresh()
	check(app.hud.experience_label.text == "满级" and app.hud.experience_bar.value == app.hud.experience_bar.max_value,"cap shows filled meter without zero division")
	check(Readout.next_goal("CH03",3600).contains("装备"),"max-level target redirects to build choices")
	Words.set_locale("en")
	check(Readout.next_goal("CH03",0).contains("Right click"),"English growth uses a readable mouse label")
	Words.set_locale("zh_CN")
	await app.room.combat_audio.wait_for_cleanup()
	Game.finish_run("abandoned")
	await frames()
	check(app.screen.find_child("NextGrowthGoal",true,false) != null,"normal settlement presents the next growth goal")
	check(app.screen.find_child("ExtractedEquipmentReceipt",true,false) != null,"settlement shows real equipment receipt")
	await capture("result")
	app.set_process(false)
	await app.music.wait_for_cleanup()
	app.free()
	viewport.free()
	await frames(8)
	print("GROWTH FEEDBACK: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
