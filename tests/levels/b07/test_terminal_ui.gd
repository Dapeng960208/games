extends Node
## Controlled lifecycle fixtures; separate from the normal-AI live probe.
const Launcher = preload("res://scripts/levels/b07/world/candidate_scene.gd")
const Layout = preload("res://scripts/levels/b07/art/l37_skill_card_layout.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("B07 TERMINAL "+label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	for difficulty: int in [0,2]:
		for outcome: String in ["death","abandoned"]:
			var launch := Launcher.new()
			launch.auto_start = false
			# Controlled fixture freezes AI while testing the real damage/settlement
			# and presentation callbacks. The live probe does not use this freeze.
			launch.process_mode = Node.PROCESS_MODE_DISABLED
			add_child(launch)
			check(launch.start_candidate("CH01",difficulty,true),"start/re-enter "+outcome+" D"+str(difficulty))
			if Game.run == null: get_tree().quit(1); return
			check(launch.hud.is_visible_in_tree() and launch.hud.interaction_enabled,"fresh HUD visible and interactive")
			check(launch.hud.get_script().resource_path=="res://scripts/presentation/hud/hud.gd","reuse unchanged shared HUD")
			check(launch.finished_outcome.is_empty() and not launch.room.input_blocked,"fresh lifecycle reset")
			launch._on_run_finished({"run_id":"unrelated","outcome":"death"})
			check(launch.hud.visible and launch.finished_outcome.is_empty(),"ignore other run result")
			var brains: Array[Dictionary] = []
			for actor: Node in launch.room.enemies.get_children():
				brains.append(actor.brain.current_skill().duplicate(true))
				var badge: Node2D=actor.get_node_or_null("EnemySkillBadge")
				if badge != null:
					badge.info={"fixture":true}; badge.command={"fixture":true}
					badge.show_detail=true; badge.show()
			if outcome=="death":
				Game.damage_player(float(Game.run.max_hp)*1000.0,{"damage_type":"physical"})
			else:
				Game.finish_run("abandoned")
			check(Game.run==null and launch.finished_outcome==outcome,"real settlement completed")
			launch._process(0.0)
			check(not "F: rotate" in launch.status.text and not "light altar" in launch.status.text,"terminal status retires gameplay instructions")
			check(not launch.hud.visible and not launch.hud.interaction_enabled and not launch.hud.is_processing(),"combat values and skills retired")
			check(launch.room.input_blocked,"no terminal inputs")
			for repeat_index in 3:
				if Layout.enabled(launch.room): Layout.publish(launch.room)
				var batch: Dictionary=launch.room.get_meta(Layout.BATCH_META,{})
				check(batch.get("terminal",false) and batch.get("selected_ids",[-1]).is_empty() and batch.get("placements",{"stale":true}).is_empty(),"empty terminal batch stays empty")
				for actor: Node in launch.room.enemies.get_children():
					var badge: Node2D=actor.get_node_or_null("EnemySkillBadge")
					if badge != null: check(not badge.visible and not badge.show_detail and badge.info.is_empty() and badge.command.is_empty() and badge.last_detail_draw.is_empty(),"badge presentation cleared")
			var index := 0
			for actor: Node in launch.room.enemies.get_children():
				check(actor.brain.current_skill()==brains[index],"terminal UI does not rewrite combat commands")
				index += 1
			check(await launch.room.combat_audio.wait_for_cleanup(),"audio released before returning from fixture")
			launch.free()
			await get_tree().process_frame
	print("B07 TERMINAL UI: ",checks," checks, ",failures," failures; controlled lifecycle, review=", "--b07-convergence-review" in OS.get_cmdline_user_args())
	get_tree().quit(1 if failures else 0)
