extends "res://tests/combat/test_enemy_integration.gd"
## Regression for real SalvagerPlayer targets, whose life is Game.run-owned and
## who intentionally have no is_alive method. Actual actor/brain/runtime only.
func _run() -> void:
	if not Game.profile_path.contains("test_b05_actor_live"):
		push_error("B05 actor live requires its isolated profile")
		get_tree().quit(2)
		return
	Game.run=null
	check(Game.new_profile() and Game.start_run(),"isolated real run starts")
	for d in [0,4]:
		for id: String in ["B05-M01","B05-M02","B05-M04"]:
			fixture()
			room.difficulty=d
			room.combat_audio.audible=false
			Game.run.max_hp=100000;Game.run.stats.max_hp=100000;Game.run.hp=100000
			room.player.invulnerable=0
			var actor: EnemyActor=room.spawn_enemy(Vector2(1100,800),id,21,{"profile":Profiles.resolve(id,21,"normal",2,d),"reward_enabled":false})
			check(actor!=null,id+" actual actor D"+str(d))
			if actor==null: continue
			var ally: EnemyActor
			var before:=0.0
			if id=="B05-M04":
				ally=room.spawn_enemy(Vector2(1150,850),"B05-M01",21,{"profile":Profiles.resolve("B05-M01",21,"normal",2,d),"reward_enabled":false})
				ally.training_ai_disabled=true
				ally.health.current=1
				before=ally.health.current
			check(not room.player.has_method("is_alive") and actor.brain._alive(room.player),"actual player life-query compatibility")
			var hp_before: float=Game.run.hp
			check(until(func(): return actor.brain.cycle>0,6),id+" actual brain releases its active")
			if id=="B05-M02":
				var landing_seen:=false
				for pending: Dictionary in room.enemy_skills.jobs:
					if bool(pending.get("b05_landed",false)) and int(pending.get("owner_id",0))==actor.get_instance_id():
						landing_seen=true
						check(Vector2(pending.origin).is_equal_approx(Vector2(pending.target)),"real M02 job warning center equals locked landing")
						check(room.enemy_skills.shape_contains(pending,Vector2(pending.target),0) and not room.enemy_skills.shape_contains(pending,actor.position,0),"real delayed warning covers target, not caster")
				check(landing_seen,"actual M02 pending landing exists before impact")
			step(.5)
			if id=="B05-M04": check(ally.health.current>before,"actual channel heals one real ally")
			else: check(Game.run.hp<hp_before,id+" actual runtime damages real player")
			check(not actor.brain.current_skill().is_empty(),id+" source-stamped presentation remains live")
			check(await room.combat_audio.wait_for_cleanup(),"audio jobs finish")
	fixture()
	room.combat_audio.audible=false
	Game.run.max_hp=100000;Game.run.stats.max_hp=100000;Game.run.hp=100000
	var boss: BossActor=load(AssetCatalog.resolve("res://scripts/gameplay/bosses/boss_actor.gd")).new()
	boss.room=room;boss.position=Vector2(1100,800)
	check(boss.configure_boss("BO05",0,251804,2),"actual BO05 factory")
	room.enemies.add_child(boss)
	check(until(func(): return not boss.boss_brain._actions_used.is_empty(),6),"actual BO05 acquires real player and releases")
	check(Game.run.hp<100000,"actual BO05 damages player")
	check(await room.combat_audio.wait_for_cleanup(),"boss audio cleanup")
	room.free();Game.run=null
	print("B05_ACTOR_LIVE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
