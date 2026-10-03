extends Node
const Codex=preload("res://scripts/presentation/screens/monster_codex.gd")
const Skills=preload("res://scripts/levels/b06/combat/enemy_skills.gd")
const Abilities=preload("res://scripts/domain/combat/enemy_ability_catalog.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok: failures+=1;push_error(label)
func _ready()->void:
 run.call_deferred()
func run()->void:
 var ids:=Codex.entry_ids()
 if not preload("res://scripts/infrastructure/content/runtime_rules.gd").chapter_enabled(6):
  check(ids.size()==58 and "BO06" not in ids,"default released catalog unchanged")
  check(Codex.resolved_entry("BO06",30,4).is_empty(),"default fortress resolver closed")
  check(Codex.boss_skill_entries("BO06",4).is_empty(),"default fortress guide closed")
  print("B06_CODEX_GATE checks=%d failures=%d"%[checks,failures])
  get_tree().quit(1 if failures else 0);return
 check(ids.size()==96,"90 ordinary plus six bosses")
 check(ids.count("BO06")==1,"BO06 registered once")
 get_window().size=Vector2i(2560,1440)
 get_window().content_scale_size=Vector2i(1280,720)
 get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
 Words.set_locale("zh_CN")
 var guide:=Codex.new();guide.theme=GameStyle.make_theme();add_child(guide)
 guide.configure(func():pass,"B06")
 check(guide.filtered_ids().size()==19,"B06 filter includes fortress")
 for n:int in range(1,19):
  var id:="B06-M%02d"%n
  for tier:int in range(5):
   var profile:=Codex.resolved_entry(id,30,tier)
   var entries:=Abilities.all_skills(id,tier,profile)
   check(entries.size()==3,id+" has three authored tiers")
   for row:Dictionary in entries:
    var expected:=Skills.active(Skills.profile(id,30,maxi(tier,int(row.min_difficulty))),Vector2.ZERO,Vector2(300,0),true,true)
    check(row.command==expected,"same runtime command")
    check(row.tell_seconds==expected.tell and row.lock_seconds==expected.lock,"same compressed warning")
    check(row.unlocked==(tier>=row.min_difficulty),"exact unlock gate")
   guide.difficulty=tier;guide._show_entry(id)
   check(not guide.detail.get_meta("resolved_profile").is_empty(),"actual inspector resolves")
 for tier:int in range(5):
  var boss:=Codex.resolved_entry("BO06",30,tier)
  check(boss.boss_id=="BO06" and boss.phase_thresholds==[.7,.4],"actual boss identity and phases")
  var entries:=Codex.boss_skill_entries("BO06",tier)
  check(entries.size()==6,"six actual fortress actions")
  for index:int in entries.size():
   var row:Dictionary=entries[index]
   var gate:int=Skills.BOSS_GATES[index]
   check(row.command==Skills.boss_action(Skills.boss_profile(maxi(tier,gate)),Skills.BOSS_ACTIONS[index],Vector2.ZERO,Vector2(300,0),1),"boss command source equality")
   check(row.unlocked==(tier>=gate),"boss difficulty gate")
   check(row.stages.size()==int(row.command.get("stage_count",1)),"all warned stages displayed")
   for stage:int in row.stages.size():
    check(row.stages[stage]==Skills.boss_action(Skills.boss_profile(maxi(tier,gate)),Skills.BOSS_ACTIONS[index],Vector2.ZERO,Vector2(300,0),1,stage),"same follow-up command")
  guide.difficulty=tier;guide._show_entry("BO06")
  check(guide.detail.find_child("Portrait_BO06",true,false).texture!=null,"native fortress portrait present")
 if DisplayServer.get_name()!="headless":
  for id:String in ["B06-M18","BO06"]:
   guide.difficulty=4;guide._show_entry(id)
   await get_tree().process_frame
   await RenderingServer.frame_post_draw
   check(get_viewport().get_texture().get_image().save_png(OS.get_environment("GAMES_TEST_OUTPUT_DIR").path_join(id+"-codex-fixed.png"))==OK,"actual 2K screenshot")
 guide.queue_free();await get_tree().process_frame
 print("B06_CODEX checks=%d failures=%d"%[checks,failures])
 get_tree().quit(1 if failures else 0)
