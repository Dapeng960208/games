extends "res://tests/levels/b06/test_b06_equipment_effects_live.gd"
## Reuses legal factory fixtures; only exercises the actual SG W/R adapter.
func run_checks()->void:
 if not Game.profile_path.contains("test_b06_equipment_r_live"):get_tree().quit(2);return
 check(Game.new_profile() and Game.start_run(),"isolated R run")
 _actual_rounds()
 _cancel_and_reset()
 if is_instance_valid(room):
  check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
  room.free()
 Game.run=null
 print("B06 R LIVE: ",checks," checks; failures=",failures)
 get_tree().quit(0 if failures.is_empty() else 1)
func setup_mark()->Array:
 fixture("CH02","B06-SG")
 var first:=target(Vector2(100,0));var second:=target(Vector2(200,0))
 check(room.player.cast_skill("secondary",first.position),"real W cast")
 step(.8)
 check(first.health.current<first.health.maximum and second.health.current<second.health.maximum,"actual W pierces two actors")
 var mark:Dictionary=room.player.loadout._b06_tide_mark
 check(not mark.is_empty() and mark.target.get_ref()==first,"tide mark binds first pierced actor")
 for projectile:Node in room.projectiles.get_children():projectile.free()
 Game.run.resource=Game.run.stats.resource_max
 return [first,second]
func emit_without_moving_projectiles(seconds:float)->void:
 var remaining:=seconds
 while remaining>0:
  var dt:=minf(.01,remaining)
  room.player.abilities.tick(dt)
  room.player.loadout.tick(dt)
  remaining-=dt
func _actual_rounds()->void:
 var targets:=setup_mark()
 var first:EnemyActor=targets[0];var second:EnemyActor=targets[1]
 check(room.player.cast_skill("ultimate",first.position),"actual R accepted")
 emit_without_moving_projectiles(2.5)
 var shots:Array=[]
 for projectile:Node in room.projectiles.get_children():
  if projectile.source==&"ultimate":shots.append(projectile)
 check(shots.size()>=4,"R actually emits at least four rounds")
 if shots.size()<4:return
 var bonus_count:=0
 for i:int in shots.size():
  var bonus:Dictionary=shots[i].options.get("b06_r_bonus",{})
  if not bonus.is_empty():
   bonus_count+=1
   check(i<3 and bonus.r_shot_ordinal==i+1,"only first three emitted ordinals")
   check(bonus.target_id==str(first.get_instance_id()),"each packet remains bound to W first target")
   near(bonus.damage,Numbers.integer(float(Game.run.stats.attack)*.12),"actual extra 0.12P")
 check(bonus_count==3,"exactly three actual projectile bonuses")
 var first_packets:Array=[];var second_packets:Array=[]
 first.health.damaged.connect(func(amount:float):first_packets.append(amount))
 second.health.damaged.connect(func(amount:float):second_packets.append(amount))
 shots[0].hit(first)
 check(first_packets.size()==2,"marked actual projectile delivers direct plus equipment packet")
 if first_packets.size()==2:near(float(first_packets[1]),Numbers.integer(float(Game.run.stats.attack)*.12),"actual health loss from extra packet equals 0.12P")
 var hp:float=first.health.current
 shots[0].hit(first)
 near(first.health.current,hp,"repeated projectile callback cannot duplicate damage")
 shots[1].direction=Vector2.DOWN
 shots[1].hit(second)
 check(second_packets.size()==1,"redirected round hitting other actor has no extra packet")
 shots[2].hit(first)
 check(first_packets.size()==4,"third actual round still hits bound mark")
 shots[3].hit(first)
 check(first_packets.size()==5,"fourth round has only direct packet")
 var repeated:Dictionary=shots[0].options.duplicate(true)
 repeated.r_shot_ordinal=1
 check(room.player.loadout.b06_r_shot(repeated).is_empty(),"duplicate first-shot receipt cannot mint another bonus")
func _cancel_and_reset()->void:
 var targets:=setup_mark()
 var first:EnemyActor=targets[0]
 var hp:float=first.health.current
 check(room.player.cast_skill("ultimate",first.position),"cancel fixture actual R accepted")
 room.player.abilities.cancel()
 emit_without_moving_projectiles(3)
 check(room.projectiles.get_child_count()==0,"cancel before emission creates no projectiles")
 near(first.health.current,hp,"cancelled un-emitted rounds cause no damage")
 check(not room.player.loadout.effects.cooldowns.has("B06-SG_6"),"cancel before emission spends no SG6 ICD")
 check(not room.player.loadout._b06_tide_mark.is_empty(),"un-emitted cast retains existing mark")
 room.player.loadout.event("room_enter",{"room_id":"L32"})
 check(room.player.loadout._b06_tide_mark.is_empty(),"room entry clears target binding")
 targets=setup_mark()
 room.player.loadout.rebind(Game.run.stats.loadout,Game.run.stats)
 check(room.player.loadout._b06_tide_mark.is_empty(),"equipment rebind clears target binding")
