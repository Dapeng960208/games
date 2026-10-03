extends RefCounted
## Display adapter: authored unlock text plus commands from the actual executor.
const Skills=preload("res://scripts/combat/b06_enemy_skills.gd")
const Content=preload("res://scripts/world/b06_content.gd")
static func all_skills(id:String, tier:int, resolved:Dictionary={}) -> Array[Dictionary]:
 var result:Array[Dictionary]=[]
 var source:=Content.enemy(id)
 if source.is_empty(): return result
 for gate:int in [0,2,4]:
  var p:=Skills.profile(id,int(resolved.get("enemy_level",30)),maxi(tier,gate),str(resolved.get("rank","normal")),resolved.get("enemy_calibration_snapshot",null),int(resolved.get("b06_numerical_version",0)))
  var command:=Skills.active(p,Vector2.ZERO,Vector2(300,0),true,true)
  var authored:Dictionary=source.skills[str(gate)]
  var effect:String=str(authored.source_text).split("（")[0]
  if gate==0 and id=="B06-M13": effect=effect.replace("引导1.5s","预警引导后")
  if gate==0 and id=="B06-M14": effect=effect.replace("露出水迹1.0s后","水迹预警后")
  result.append({"ability_id":id+":D"+str(gate),"name":source.name+" · D"+str(gate),"name_en":source.name_en+" · D"+str(gate),"effect":effect,"effect_en":effect,"trigger":"基础招式" if gate==0 else "累计难度强化（环境条件仍需满足）","trigger_en":"Base action" if gate==0 else "Cumulative difficulty upgrade; environmental conditions still apply","counter":source.counter_and_drop_text,"counter_en":command.counter_cue_en,"min_difficulty":gate,"unlocked":tier>=gate,"replaced":false,"tell_seconds":command.tell,"lock_seconds":command.lock,"cooldown":command.cooldown,"command":command,"preview_wet":true,"preview_high":true})
 return result
