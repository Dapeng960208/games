extends SceneTree
## Focused cold-cache check: no gameplay, graphics, or player-save mutation.
const Art = preload("res://scripts/combat/b05_enemy_art.gd")
const Sampler = preload("res://scripts/ui/texture_sampler.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var before := Sampler.textures.size()
	check(Art.bank("invalid").is_empty(), "Unknown identity stays empty")
	check(Art._banks.is_empty(), "Invalid identity loads no banks")
	var first := Art.bank("B05-M01")
	check(not first.is_empty(), "Original manifest identity loads")
	check(Art._banks.size() == 1, "First species loads only one bank")
	check(Sampler.textures.size() == before + 3, "First species loads only three poses")
	check(Art.bank("B05-M01") == first, "Repeated lookup preserves cached bank")
	check(Sampler.textures.size() == before + 3, "Repeated lookup allocates no texture")
	var regenerated := Art.bank("B05-M03")
	check(not regenerated.is_empty(), "Regenerated manifest identity loads")
	check(Art._banks.size() == 2, "Second species loads only its own bank")
	check(Sampler.textures.size() == before + 6, "Two species load six poses rather than 54")
	check(str(regenerated.clips.idle[0].texture_path).begins_with(Art.REGENERATED_ROOT), "Regenerated source retained")
	check(first.clips.walk == first.clips.idle and regenerated.clips.recovery == regenerated.clips.idle, "Pose aliases preserved")
	print("B05_ART_RESIDENCY banks=%d textures_added=%d failures=%d" % [Art._banks.size(), Sampler.textures.size()-before, failures])
	quit(1 if failures else 0)
