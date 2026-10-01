extends "res://tests/test_boss_tactics.gd"
const Abilities = preload("res://scripts/combat/boss_ability_catalog.gd")
const Presentation = preload("res://scripts/combat/boss_skill_presentation.gd")

func run_checks() -> void:
	if not Game.profile_path.contains("test_boss_unlocks"): get_tree().quit(2); return
	check(Game.new_profile() and Game.start_run(),"isolated production combat run")
	var total_actions := 0
	for id: String in IDS:
		var last_count := 0
		for difficulty: int in 5:
			var sim := fixture(id,difficulty)
			var brain: BossBrain = sim.boss.boss_brain
			var pool := brain.skill_pool()
			check(difficulty == 0 or pool.size() == last_count+1,id+" skill pool grows at D"+str(difficulty))
			last_count = pool.size()
			for tier: int in 4:
				var action: String = Abilities.UNLOCKS[id][tier]
				var unlocked: bool = difficulty >= tier+1
				for phase_id: int in [1,2,3]: check(brain.available_actions(phase_id).has(action) == unlocked,action+" phase pool gates D"+str(difficulty))
				check(brain._build_action(sim.boss,sim.player,action).is_empty() != unlocked,action+" builder gates difficulty")
				if not unlocked:
					brain._begin_action(sim.boss,sim.player,action)
					check(brain.command.is_empty() and brain.state == &"recovery",action+" cannot be forced below its unlock")
			sim.room.free()
		for action: String in Abilities.UNLOCKS[id]:
			var sim := fixture(id,4)
			# Position a real recipient inside the new skill's authored shape.
			var brain: BossBrain = sim.boss.boss_brain
			if action in ["axe_fan","wing_storm"]: sim.player.position = sim.boss.position+Vector2(180,0)
			if action in ["eclipse_ring","seismic_crown"]: sim.player.position = sim.boss.position+Vector2(330,0)
			var source := brain._build_action(sim.boss,sim.player,action)
			if source.get("shape") == "line" and source.get("kind") in ["ground_area","projectile"]:
				var path: Array = source.paths[0]
				add_recipient(sim,Vector2(path[0]).lerp(Vector2(path[1]),.5))
			if action == "amber_trap": add_recipient(sim,Vector2(source.targets[0]))
			var locked := locked_action(sim,action)
			var info := Presentation.readout(brain)
			check(info.casting and info.locked and info.title == Abilities.title(action),action+" cast UI follows actual locked action")
			check(info.remaining > 0 and info.progress > .5,action+" UI timer and continuous progress")
			var old_casts: int = sim.boss.casts.size()
			tick(sim,float(brain.state_time)+.01)
			check(sim.boss.casts.size() == old_casts+1,action+" releases once")
			brain.state_time = 10.0 # Keep autonomous follow-ups out of this one-cast check.
			tick(sim,2.0)
			var hits := 0
			for actor: Node2D in sim.room.recipients: hits += actor.hits.size()
			check(hits > 0,action+" actual runtime damages a warned recipient")
			check(sim.runtime.hazards.size() <= 2,action+" keeps finite hazard limit")
			sim.room.free()
			total_actions += 1
	Game.finish_run("abandoned")
	print("BOSS UNLOCKS: ",checks-failures,"/",checks," passed; ",total_actions," new production skills")
	get_tree().quit(1 if failures else 0)
