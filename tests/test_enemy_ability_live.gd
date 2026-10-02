extends "res://tests/test_enemy_integration.gd"
## Scoped production room/actor/runtime check plus optional GPU captures.
## No natural progression runs. Use --test-profile containing this test name.
const AbilityCatalog = preload("res://scripts/combat/enemy_ability_catalog.gd")
const SkillPresentation = preload("res://scripts/combat/enemy_skill_presentation.gd")

func _run() -> void:
 if not Game.profile_path.contains("test_enemy_ability_live"):
  get_tree().quit(2)
  return
 for action: String in ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
  if not InputMap.has_action(action): InputMap.add_action(action)
 get_tree().create_timer(90.0).timeout.connect(func(): push_error("Ability live timeout"); get_tree().quit(1))
 check(Game.new_profile() and Game.start_run(),"isolated real run starts")
 for difficulty: int in [0,4]:
  for index: int in range(37,55):
   fixture()
   room.combat_audio.audible = false
   room.difficulty = difficulty
   Game.run.max_hp = 100000.0
   Game.run.stats.max_hp = 100000.0
   Game.run.hp = 100000.0
   var id: String = "M%02d" % index
   var actor: MineEnemy = room.spawn_enemy(Vector2(1100,800),id,20,{"profile":Profiles.resolve(id,20,"normal",2,difficulty)})
   check(actor != null,id+" real actor spawns at D"+str(difficulty))
   if actor == null: continue
   var seen_casts: Dictionary = {}
   var seen_unlock: bool = false
   for frame: int in 2200:
    if id == "M51" and actor.brain.phase == &"execute" and str(actor.brain.current_skill().get("kind","")) == "counter":
     actor.take_damage(1.0,&"primary",Vector2.LEFT,{"damage_type":"true"})
    step(.025)
    if actor.brain.phase == &"execute":
     var command: Dictionary = actor.brain.current_skill()
     seen_casts[str(command.get("ability_id",""))] = true
     if int(command.get("unlock_difficulty",0))>0: seen_unlock = true
    if actor.brain.cycle >= 1: break
   check(seen_casts.size()>=1 and actor.brain.cycle>=1,id+" production brain releases and completes finite real cycle")
   check(actor.brain.selected_difficulty==difficulty and seen_unlock==(difficulty>0),id+" selected difficulty enters live emitted sequence")
   check(room.enemy_skills.active_effect_count()<=128 and live_actors().size()<=18,id+" live effects preserve finite caps")
 # Single-use bombers choose the newest unlocked prelude at their selected D.
 for difficulty: int in range(1,5):
  fixture()
  room.difficulty = difficulty
  Game.run.max_hp = 100000.0
  Game.run.stats.max_hp = 100000.0
  Game.run.hp = 100000.0
  var actor: MineEnemy = room.spawn_enemy(Vector2(1120,800),"M36",20,{"profile":Profiles.resolve("M36",20,"normal",2,difficulty)})
  var fired: Dictionary = {}
  for frame: int in 1700:
   step(.025)
   if actor.brain.phase == &"execute":
    var command: Dictionary = actor.brain.current_skill()
    fired[str(command.get("ability_id",""))] = command
   if actor.brain.phase == &"spent": break
  var discharge: int = 0
  var chosen: bool = false
  for command: Dictionary in fired.values():
   if command.kind=="ground_area" and command.shape=="ring": discharge += 1
   if int(command.get("unlock_difficulty",0))==difficulty: chosen=true
  check(chosen and discharge==1 and actor.brain.phase==&"spent","M36 D%d emits newest prelude and exactly one explosion" % difficulty)
 await captures()
 if is_instance_valid(room):
  await room.combat_audio.wait_for_cleanup()
  room.free()
 print("ENEMY ABILITY LIVE: %d checks, %d failures" % [checks,failures])
 get_tree().quit(0 if failures==0 else 1)

func captures() -> void:
 if DisplayServer.get_name()=="headless": return
 for english: bool in [false,true]:
  for reduced: bool in [false,true]:
   fixture()
   room.combat_audio.audible = false
   room.difficulty = 4
   Words.set_locale("en" if english else "zh_CN")
   Game.profile.settings.reduced_fx = reduced
   Game.profile.settings.enemy_skill_paths = not reduced
   room.player.position = Vector2(1200,800)
   var ids: Array[String] = ["M37","M38","M39","M40","M41","M42","M43","M44","M45","M46","M47","M48","M49","M50","M51","M52","M53","M54"]
   var actors: Array[MineEnemy] = []
   for index: int in ids.size():
    var point := room.player.position+Vector2.from_angle(index*TAU/18.0)*165.0
    var actor: MineEnemy = room.spawn_enemy(point,ids[index],20,{"profile":Profiles.resolve(ids[index],20,"normal",2,4)})
    if actor != null: actors.append(actor)
   # Advance each real brain through its spawn grace and actual tell; keep
   # actions at their own reached state for a readable dense-crowd capture.
   for actor: MineEnemy in actors:
    for frame: int in 400:
     actor._physics_process(.025)
     if actor.brain.phase == &"locked": break
    actor.body_visual.advance(.016)
   room.player.set("_automatic_attack_target",weakref(actors[1]))
   for actor: MineEnemy in actors: actor.body_visual.advance(.016)
   room.enemy_telegraphs.refresh()
   var details: int = 0
   for actor: MineEnemy in actors:
    check(actor.body_visual.skill_badge.visible,actor.enemy_id+" persistent identity badge visible")
    if actor.body_visual.skill_badge.show_detail: details += 1
   check(details<=2 and details>0,"dense real room keeps at most two detailed cards")
   check(room.enemy_telegraphs.snapshot().size()>0,"essential warnings remain with paths hidden and reduced FX")
   room.camera.global_position = room.player.global_position
   room.camera.force_update_scroll()
   room.queue_redraw()
   for frame: int in 3: await get_tree().process_frame
   await RenderingServer.frame_post_draw
   var bitmap: Image = get_viewport().get_texture().get_image()
   var output: String = Game.profile_path.get_base_dir().path_join("monster_skills_%s_%s.png" % ["en" if english else "zh","reduced" if reduced else "full"])
   check(not bitmap.is_empty() and bitmap.save_png(output)==OK,"capture real monster skill UI "+output)
   print("ENEMY_ABILITY_CAPTURE "+output)
