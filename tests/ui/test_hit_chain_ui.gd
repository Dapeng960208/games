extends "res://tests/combat/test_hit_chain.gd"
## Real original-hit packets feed HUD, buff details and release metadata.

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_hit_chain_ui"):
		quit(2)
		return
	check(game.new_profile() and game.start_run(), "isolated UI run")
	for hero: String in ["CH01","CH02","CH03"]:
		fixture(hero)
		var hud: Control = load(AssetCatalog.resolve("res://scripts/presentation/hud/hud.gd")).new()
		hud.room = room
		hud.size = Vector2(1280,720)
		hud.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(hud)
		var target := dummy()
		check(not hud.hit_chain_readout.visible, hero + " empty chain has no permanent overlay")
		for n in range(1,101):
			hit(target,"ui:"+str(n))
			if n not in [1,10,25,50,75,100]: continue
			hud.refresh()
			check(int(hud.hit_chain_readout.state.count) == n and hud.hit_chain_readout.visible, hero + " actual x"+str(n)+" shown")
			check(hud.buff_info("hit_chain").name.contains("+%.1f%%" % (n*.5)), "buff describes live damage bonus")
			check(is_equal_approx(float(hud.buff_info("hit_chain").remaining),room.player.hit_chain.remaining), "buff and ribbon share actual timer")
			var feedback: Node = room.player.get_node("HeroFeedback")
			check(feedback.effects[-1].kind == ("chain_tick" if n == 1 else "chain_burst"), "milestone callback emits real role VFX")
		for resolution: Vector2 in [Vector2(900,600),Vector2(1280,720),Vector2(1920,1080)]:
			hud.size = resolution
			hud._apply_layout()
			var rect: Rect2 = hud.hit_chain_readout.get_rect()
			check(Rect2(Vector2.ZERO,resolution).encloses(rect), "counter stays within viewport")
			for other: Control in [hud.status_panel,hud.location_panel,hud.gold_label,hud.relic_row,hud.buff_row,hud.quest_panel,hud.skill_dock,hud.equipment_actions,hud.passive_panel]:
				check(not rect.intersects(other.get_rect()), "combo avoids " + str(other.name) + " at " + str(resolution))
		for locale: String in ["zh_CN","en"]:
			Words.set_locale(locale)
			hud.refresh()
			var font: Font = hud.hit_chain_readout.get_theme_default_font()
			check(font.get_string_size("x100",HORIZONTAL_ALIGNMENT_LEFT,-1,48).x < 122, "largest animated count fits its separate number column")
			check(hud.buff_info("hit_chain").description.contains("100"), "both languages explain cap")
		check(hud.hit_chain_readout.mouse_filter == Control.MOUSE_FILTER_IGNORE, "counter preserves mouse attacks/movement")
		hit(target,"after_cap")
		check(room.player.get_node("HeroFeedback").effects[-1].kind == "chain_tick", "new capped hit refreshes buff without repeating milestone burst")
		_check_variants(hero,target)
		room.player.hit_chain.tick(4.0)
		hud.refresh()
		check(not hud.hit_chain_readout.visible and not hud.active_buffs.has("hit_chain"), "expired buff and counter disappear together")
		hud.free()
	Words.set_locale("zh_CN")
	await room.combat_audio.wait_for_cleanup()
	room.free()
	print("HIT CHAIN UI: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _check_variants(hero: String, target: Node2D) -> void:
	var feedback: Node = room.player.get_node("HeroFeedback")
	for index in 6:
		room.player.shot_cooldown = 0.0 # Cadence has independent production acceptance.
		var expected: int = room.player.basic_attack_variant()
		check(room.player.fire(Vector2.RIGHT), hero + " accepted public attack for variant")
		if hero == "CH01": room.player._tick_attack(.13)
		else:
			var projectile: Node = room.projectiles.get_child(-1)
			check(int(projectile.options.basic_variant) == expected, hero + " projectile captures release variant")
			projectile.hit(target)
		var releases: Array = feedback.effects.filter(func(e: Dictionary): return str(e.get("slot","")) == "basic")
		check(int(releases[-1].variant) == index%3, hero + " three-pulse attack pattern cycles")
		check(int(room.impact_feedback.events[-1].basic_variant) == index%3, hero + " contact matches released variant")
		var before: int = feedback.basic_events
		check(not room.player.fire(Vector2.RIGHT) and feedback.basic_events == before, "cooldown rejection never advances visual pattern")
