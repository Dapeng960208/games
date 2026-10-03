extends Node
## Targeted B08 view/pause contract. Invoke per hero; no gameplay or save grants.
const Host = preload("res://scripts/levels/b08/presentation/hud_host.gd")
const Gate = preload("res://scripts/levels/b08/candidate_gate.gd")
const SharedHUD = preload("res://scripts/presentation/hud/hud.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("B08 HUD: "+label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func run() -> void:
	if not Gate.enabled() or not OS.get_cmdline_user_args().has("--b08-existing-hud"):
		get_tree().quit(2)
		return
	var permanent_profile: Dictionary = Game.profile.duplicate(true)
	var had_profile := Game.has_profile
	var room = load("res://scenes/gameplay/world/b08_candidate.tscn").instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	await get_tree().process_frame
	check(room.layout_id == "L43" and Host.enabled_for(room),"explicit L43 candidate gate")
	if room.layout_id != "L43":
		room.free()
		get_tree().quit(2)
		return
	var host = room.find_child("B08CombatUI",true,false)
	if host == null:
		host = Host.new()
		host.room = room
		room.add_child(host)
	await get_tree().process_frame
	var hud = host.hud
	check(hud != null and hud.get_script().get_base_script() == SharedHUD,"original combat HUD inheritance")
	if hud == null:
		room.free()
		get_tree().quit(1)
		return
	var trial_profile: Dictionary = Game.profile.duplicate(true)
	var original_receipt: Dictionary = Game.run.live_receipt().duplicate(true)
	var profile_existed := FileAccess.file_exists(Game.profile_path)
	var profile_hash := FileAccess.get_sha256(Game.profile_path) if profile_existed else ""
	check(Game.profile_path.begins_with("user://test_b08_candidate/"),"isolated profile")
	check(hud.skill_slots.size() == 5 and hud.inventory_button.visible,"all shared skills and backpack remain visible")
	check(hud.hero_label.text.contains(Game.run.hero_id) or hud.hero_label.text.contains(GameStyle.content_text(ContentRegistry.hero(Game.run.hero_id),"name")),"current hero identity")
	check(hud.health_bar.value == Game.run.hp and hud.resource_bar.value == Game.run.resource,"live hero meters")
	check(not hud.passive_snapshot.is_empty() and not hud.passive_title.text.is_empty(),"live existing class passive")
	var saved_cooldown: float = room.player.cooldowns.get("q",0.0)
	room.player.cooldowns["q"] = 2.75
	hud.refresh()
	check(is_equal_approx(float(hud.skill_info("q").cooldown),2.75),"real cooldown read without replacement logic")
	room.player.cooldowns["q"] = saved_cooldown
	var original_locale := Words.locale
	for locale: String in ["zh_CN","en"]:
		Words.set_locale(locale)
		hud.refresh()
		var status: Dictionary = hud.wave_status()
		check(status.total == 1 and status.completed == 0 and status.alive == 3 and not status.exit_ready,"authored wave and live enemies / "+locale)
		check(hud.quest_progress.text.contains("0/1") and not hud.quest_reward.text.contains("30"),"finite wave progress and no fake XP / "+locale)
		check(hud.room_identity_plate.design.chapter == 8 and hud.room_identity_plate.layout.room_id == "L43","B08 room identity / "+locale)
		check(hud.room_identity_plate.ground_polygon.is_empty(),"no catalog fallback advertised as ground / "+locale)
		check(hud.room_identity_plate.layout.objective_points[0] == room._lane("lane_0").vane,"actual vane coordinate on shared sketch / "+locale)
		hud.hovered_control = hud.quest_button
		hud._update_tooltip()
		check(hud.tooltip_panel.visible and hud.tooltip_body.text.contains(hud.quest_reward.text),"honest quest tooltip / "+locale)
	Words.set_locale(original_locale)
	hud.hovered_control = null
	hud.refresh()
	await check_panels(host,room)
	check_snapshot(trial_profile,Game.profile,"trial profile")
	var current_receipt: Dictionary = Game.run.live_receipt()
	# Game is an autoload outside the disabled room. Its _process advances only
	# this top-level clock while the test awaits unpaused GUI frames.
	check(float(current_receipt.elapsed) >= float(original_receipt.elapsed),"natural run clock stays monotonic")
	print("B08_HUD_RECEIPT_CLOCK before=",original_receipt.elapsed," after=",current_receipt.elapsed)
	check_snapshot(original_receipt,current_receipt,"run receipt",["elapsed"])
	for actor: Node in room.enemies.get_children():
		if actor.static_actor: continue
		# CombatHealth owns dead/depleted; writing current alone is not death.
		check(actor.health.damage(float(actor.health.current)+1.0),"real combatant health depletion "+str(actor.enemy_id))
		check(not actor.is_alive(),"depletion marks combatant dead "+str(actor.enemy_id))
	hud.refresh()
	check(hud.wave_status().completed == 1 and hud.wave_status().exit_ready,"clear readout follows actual exit availability")
	check(hud.quest_progress.text.contains("1/1") and hud.objective_bar.value == 1,"completed finite-wave display")
	check_snapshot(trial_profile,Game.profile,"profile after actual candidate clears")
	check_snapshot(current_receipt,Game.run.live_receipt(),"receipt after actual candidate clears")
	check(FileAccess.file_exists(Game.profile_path) == profile_existed and (not profile_existed or FileAccess.get_sha256(Game.profile_path) == profile_hash),"no profile file writes")
	check(Game.run.completed_reward_ids.is_empty() and Game.run.boss_defeats.is_empty(),"no candidate rewards or chapter completion")
	host.show_backpack()
	host.close_panels()
	check(not get_tree().paused and not room.input_blocked,"explicit teardown clears modal pause")
	# Query the narrow room gate without changing the battle before real death.
	room.layout_id = "L44"
	check(not Host.enabled_for(room),"L44 cannot enable unreviewed HUD adapter")
	room.layout_id = "L43"
	hud.refresh()
	var terminal_max_hp: float = Game.run.max_hp
	var terminal_hero: String = hud.hero_label.text
	var terminal_resource: float = Game.run.resource
	host.show_backpack()
	check(get_tree().paused,"terminal damage fixture starts with an open panel")
	Game.damage_player((Game.run.max_hp+Game.run.shield)*100.0,{"damage_type":"true","source_id":"b08_hud_contract","source_name":"B08 HUD contract"})
	check(Game.run == null and Game.last_result.get("outcome","") == "death","real lethal damage clears the demo run")
	check(Game.profile == permanent_profile and Game.has_profile == had_profile,"death restores the pre-demo profile rather than retaining the trial profile")
	check(host.candidate_finished and host.modals.is_empty() and not get_tree().paused and room.input_blocked,"death dismisses panels and blocks combat input")
	check(hud.last_live_state.hp == 0 and hud.health_bar.value == 0 and hud.health_bar.max_value == terminal_max_hp,"terminal controls show the real zero HP snapshot")
	check(hud.health_label.text == Words.text("HUD_HP_COMPACT",{"hp":0,"max":ceili(terminal_max_hp)}) and hud.hero_label.text == terminal_hero,"terminal HP label and original trial hero survive profile restoration")
	check(hud.resource_bar.value == terminal_resource and hud.objective_label.text.contains("Esc") and not hud.finished_result.is_empty(),"terminal resource and explicit end message remain readable")
	hud.inventory_button.pressed.emit()
	hud.skill_slots[0].pressed.emit()
	hud.progression_button.pressed.emit()
	host.show_backpack()
	host.show_combat_details()
	check(host.modals.is_empty() and hud.inventory_button.disabled and hud.skill_slots[0].disabled,"finished candidate cannot reopen panels")
	hud.refresh()
	await get_tree().process_frame
	check(Game.run == null and hud.health_bar.value == 0 and hud.hero_label.text == terminal_hero,"later refresh cannot restore stale living or restored-profile HUD values")
	check(FileAccess.file_exists(Game.profile_path) == profile_existed and (not profile_existed or FileAccess.get_sha256(Game.profile_path) == profile_hash),"real demo death performs no profile write")
	check(await room.cleanup_for_exit(),"bounded room audio shutdown")
	room.free()
	await get_tree().process_frame
	print("B08_HUD_ADAPTER checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)

func check_snapshot(before: Dictionary, after: Dictionary, label: String, allowed_paths: Array[String] = []) -> void:
	var paths := changed_paths(before,after)
	for path: String in allowed_paths: paths.erase(path)
	if not paths.is_empty(): print("B08_HUD_SNAPSHOT_DIFF ",label," paths=",paths)
	check(paths.is_empty(),label+" unchanged except explicitly allowed paths")

func changed_paths(before: Variant, after: Variant, prefix: String = "") -> Array[String]:
	var paths: Array[String] = []
	if before is Dictionary and after is Dictionary:
		var keys: Array = before.keys()
		for key: Variant in after:
			if not keys.has(key): keys.append(key)
		for key: Variant in keys:
			var path := str(key) if prefix.is_empty() else prefix+"."+str(key)
			if not before.has(key) or not after.has(key): paths.append(path)
			else: paths.append_array(changed_paths(before[key],after[key],path))
	elif before is Array and after is Array and before.size() == after.size():
		for index: int in before.size(): paths.append_array(changed_paths(before[index],after[index],prefix+"[%d]" % index))
	elif before != after:
		paths.append(prefix)
	return paths

func check_panels(host: Node, room: Node) -> void:
	var hud = host.hud
	hud.inventory_button.pressed.emit()
	hud.inventory_button.pressed.emit()
	check(host.modals.size() == 1 and get_tree().paused and room.input_blocked,"repeated backpack click opens one paused panel")
	var backpack = host.ui.find_child("BackpackPanel",true,false)
	check(backpack != null and backpack.get_script().get_base_script().resource_path == "res://scripts/presentation/equipment/backpack_panel.gd","existing backpack inspector")
	if backpack != null:
		var equip := backpack.find_child("BackpackEquip",true,false) as Button
		var remove := backpack.find_child("BackpackUnequip",true,false) as Button
		check((equip == null or not equip.visible) and (remove == null or not remove.visible),"no unsupported visible gear mutations")
		check(not backpack.status_label.text.is_empty(),"explicit candidate backpack scope")
		backpack.find_child("BackpackAttributesTab",true,false).pressed.emit()
		check(backpack.find_child("BackpackCharacterAttributes",true,false) != null,"existing complete attribute sheet")
		backpack.find_child("CloseBackpack",true,false).pressed.emit()
	check(host.modals.is_empty() and not get_tree().paused and not room.input_blocked and room.release_gate,"close restores gameplay with release gate")
	hud.progression_button.pressed.emit()
	check(host.ui.find_child("CharacterDossier",true,false) != null and get_tree().paused,"hero button opens existing character dossier")
	host._pop_modal()
	await get_tree().process_frame
	hud.skill_slots[0].pressed.emit()
	check(host.ui.find_child("SkillDetailsBody",true,false) != null and get_tree().paused,"skill button opens existing complete skill panel")
	var attributes = host.ui.find_child("CombatAttributes",true,false)
	attributes.pressed.emit()
	check(host.modals.size() == 2,"character panel nests in skill details")
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.physical_keycode = KEY_ESCAPE
	cancel.pressed = true
	host._input(cancel)
	check(host.modals.size() == 1 and get_tree().paused,"Escape returns to previous detail panel")
	host._input(cancel)
	check(host.modals.is_empty() and not get_tree().paused,"second Escape returns to combat")
	await get_tree().process_frame
