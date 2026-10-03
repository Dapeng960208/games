extends SceneTree
const Relics=preload("res://scripts/domain/combat/class_relics.gd")
const Art=preload("res://scripts/infrastructure/assets/artwork.gd")
var checks:=0
var failures:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1;push_error("RELIC ART: "+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(Relics.art_path("ember")=="asset://ui/state_burn_v1.png","legacy alias uses current flame icon")
	check(Relics.art_path("RL02")==Relics.art_path("ember"),"stable RL02 ID shares new visual")
	check(FileAccess.file_exists(AssetCatalog.resolve(Relics.art_path("RL02"))),"replacement is existing project resource")
	check(not FileAccess.file_exists(AssetCatalog.resolve("asset://ui/relic_ember.png")),"obsolete bronze PNG retired from checkout")
	for hero: String in ["CH01","CH02","CH03"]:
		for rank in [1,2]:
			var display:=Relics.display(hero,"ember",rank)
			check(display.id=="RL02" and display.rank==rank,"identity and rank unchanged")
			check(display.art==Relics.art_path("RL02") and not str(display.description).is_empty(),"current icon keeps class effect description")
	var icon=Art.relic(root,"ember",Vector2.ZERO,Vector2(64,64))
	check(icon.texture!=null,"shared UI helper resolves replacement")
	icon.free()
	print("RELIC_ART_RETIREMENT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
