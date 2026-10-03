extends Node
const Codex=preload("res://scripts/presentation/screens/monster_codex.gd")
const Abilities=preload("res://scripts/levels/b05/combat/enemy_skills.gd")
var checks:=0
var failures:=0
func _ready() -> void:
 get_tree().create_timer(45).timeout.connect(func(): get_tree().quit(2))
 run.call_deferred()
func check(ok:bool,label:String) -> void:
 checks+=1
 if not ok: failures+=1; push_error(label)
func run() -> void:
 var output_root := OS.get_environment("GAMES_TEST_OUTPUT_DIR")
 if output_root.is_empty() or not output_root.is_absolute_path():
  push_error("Run capture through tools/testing/test_workspace.py")
  get_tree().quit(2)
  return
 var capture_folder := output_root.path_join("b05-codex")
 if not Game.profile_path.contains("test_b05_codex"): get_tree().quit(2); return
 Game.run=null
 check(Game.new_profile(),"isolated synthetic profile")
 var before:Dictionary=Game.profile.duplicate(true)
 var bytes:=FileAccess.get_file_as_bytes(AssetCatalog.resolve(Game.profile_path))
 check(Codex.entry_ids().size()==58,"normal menu remains four released regions")
 check(Codex.entry_ids(true).size()==77,"explicit preview adds eighteen enemies and one boss")
 check(not Codex.available_biomes().has("B05"),"preview never opens gameplay chapter")
 get_window().size=Vector2i(2560,1440)
 get_window().content_scale_size=Vector2i(1280,720)
 get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
 var background:=ColorRect.new();background.color=Color("e8e4d4");background.size=Vector2(1280,720);add_child(background)
 var guide:=Codex.new();guide.theme=GameStyle.make_theme();add_child(guide)
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
 var selected_ids: Array[String]=[]
 for argument: String in OS.get_cmdline_user_args():
  if argument.begins_with("--b05-pose-ids="):
   for id: String in argument.trim_prefix("--b05-pose-ids=").split(","):
    if id in preload("res://scripts/levels/b05/art/enemy_art.gd").IDS: selected_ids.append(id)
 if selected_ids.is_empty(): selected_ids.assign(["B05-M01","B05-M02","B05-M04"])
 for id:String in selected_ids:
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
   var native: Dictionary=preload("res://scripts/levels/b05/art/enemy_art.gd").entry(id)
   check(art.texture is AtlasTexture and art.texture.atlas==native.texture,"codex uses exact registered idle source")
   check(art.position.x>=8 and art.position.y>=8,"explicit eight-pixel codex safe inset")
   check(art.position.x+art.size.x<=art.get_parent().size.x-8 and art.position.y+art.size.y<=art.get_parent().size.y-8,"portrait full canvas stays in padded frame")
   var save_image: bool=not "--b05-codex-limited-capture" in OS.get_cmdline_user_args() or id in ["B05-M06","B05-M09","B05-M14","B05-M15"]
   if DisplayServer.get_name()!="headless" and tier==4 and save_image:
    await RenderingServer.frame_post_draw
    DirAccess.make_dir_recursive_absolute(capture_folder)
    check(get_viewport().get_texture().get_image().save_png(capture_folder.path_join(id+"_D"+str(tier)+".png"))==OK,"actual2K capture")
 check(Game.profile==before and FileAccess.get_file_as_bytes(AssetCatalog.resolve(Game.profile_path))==bytes,"guide does not mutate profile or file")
 print("B05_CODEX checks=%d failures=%d"%[checks,failures])
 get_tree().quit(1 if failures else 0)
