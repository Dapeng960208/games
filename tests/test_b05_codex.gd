extends Node
const Codex=preload("res://scripts/ui/monster_codex.gd")
const Abilities=preload("res://scripts/combat/b05_enemy_skills.gd")
var checks:=0
var failures:=0
func _ready() -> void:
 get_tree().create_timer(45).timeout.connect(func(): get_tree().quit(2))
 run.call_deferred()
func check(ok:bool,label:String) -> void:
 checks+=1
 if not ok: failures+=1; push_error(label)
func run() -> void:
 if not Game.profile_path.contains("test_b05_codex"): get_tree().quit(2); return
 Game.run=null
 check(Game.new_profile(),"isolated synthetic profile")
 var before:Dictionary=Game.profile.duplicate(true)
 var bytes:=FileAccess.get_file_as_bytes(Game.profile_path)
 check(Codex.entry_ids().size()==58,"normal menu remains four released regions")
 check(Codex.entry_ids(true).size()==77,"explicit preview adds18 enemies andoneboss")
 check(not Codex.available_biomes().has("B05"),"preview never opens gameplay chapter")
 get_window().size=Vector2i(2560,1440)
 get_window().content_scale_size=Vector2i(1280,720)
 get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
 var background:=ColorRect.new();background.color=Color("e8e4d4");background.size=Vector2(1280,720);add_child(background)
 var guide:=Codex.new();guide.theme=MineStyle.make_theme();add_child(guide)
 Words.set_locale("zh_CN")
 guide.configure(func():pass,"B05",true)
 guide.search_query=""
 check(guide.filtered_ids().size()==19,"full B05 collection18 enemies+boss")
 for key:String in Codex.entry_ids(true):
  if key.begins_with("B05-") or key=="BO05":
   guide._show_entry(key)
   check(not guide.detail.get_meta("resolved_profile").is_empty(),key+" actual profile exists")
 check(Codex.boss_skill_entries("BO05",4).size()==6,"actual boss brain six actions")
 # Limit visual collection to completed source identities through the real search.
 for id:String in ["B05-M01","B05-M02","B05-M04"]:
  guide.find_child("CodexSearch",true,false).text=id;guide._refresh_grid()
  for tier:int in [0,4]:
   guide.difficulty=tier;guide._show_entry(id)
   await get_tree().process_frame
   check(guide.selected_id==id,"selected original B05 identity")
   var profile:Dictionary=guide.detail.get_meta("resolved_profile")
   check(profile.enemy_level==25,"real Lv25 profile")
   var skills:=Abilities.all_skills(id,tier,profile)
   check(skills.size()==3,"D0/D2/D4 source-backed unlocks")
   check(skills[2].unlocked==(tier==4),"locked higher difficulty is explicit")
   var art:TextureRect=guide.detail.find_child("Portrait_"+id,true,false)
   check(art.texture!=null,"native matching portrait")
   check(art.size.x<=168.1 and art.size.y<=168.1,"portrait contained")
   if DisplayServer.get_name()!="headless":
    await RenderingServer.frame_post_draw
    DirAccess.make_dir_recursive_absolute("res://artifacts/b05-codex")
    check(get_viewport().get_texture().get_image().save_png("res://artifacts/b05-codex/"+id+"_D"+str(tier)+".png")==OK,"actual2K capture")
 check(Game.profile==before and FileAccess.get_file_as_bytes(Game.profile_path)==bytes,"guide does not mutate profile or file")
 print("B05_CODEX checks=%d failures=%d"%[checks,failures])
 get_tree().quit(1 if failures else 0)
