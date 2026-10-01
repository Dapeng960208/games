extends SceneTree
## Pure helper verification against frozen, approved Decimal target values.
## This does not enable the helper or prove live actor/scene integration.
const Target = preload("res://scripts/combat/enemy_numerical_v2.gd")
const Numbers = preload("res://config/numerical_rules.gd")
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const Bosses = preload("res://scripts/combat/boss_profiles.gd")
const Difficulty = preload("res://scripts/combat/enemy_difficulty.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const FrozenPath := "res://docs/balance/current_enemy_skill_inputs.json"
var checks := 0
var failures: Array[String] = []
var packet_count := 0
var zero_count := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _profile_tokens(profile: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: String in Target.PROFILE_FLATS: result.append(str(profile[key]))
	return result

func _command_tokens(source: Dictionary, profile: Dictionary, phase: int = 1) -> Array[String]:
	var original := source.duplicate(true)
	var actual := Target.command(source, profile, phase)
	check(not actual.is_empty(), "command resolves")
	if actual.is_empty(): return []
	check(actual.damage is int, "integer per-hit/each-tick packet")
	check(Target.command(actual, profile, phase) == actual, "command retry never rescales")
	check(source == original, "command inputs are deep values")
	var result: Array[String] = [str(actual.damage)]
	packet_count += 1
	if not Target.damaging(source):
		zero_count += 1
		check(actual.damage == 0, "support/movement/counter stance stays zero")
	for key: String in ["anchor_health", "cover_hp", "pod_health", "pod_break_armor_loss"]:
		if source.has(key):
			check(actual[key] is int, "integer endpoint " + key)
			result.append(key + "=" + str(actual[key]))
	var status: Dictionary = source.get("status", {})
	if Target.STATUS_RATIOS.has(str(status.get("id", ""))):
		result.append("power=" + str(actual.status.power))
		result.append("tick=" + str(Target.status_tick(actual.status)))
	for key: String in source:
		if key in ["anchor_health", "cover_hp", "pod_health", "pod_break_armor_loss", "status", "amount"]: continue
		check(source[key] == actual[key], "preserved sequence/timing/count field " + key)
	if not status.is_empty():
		for key: String in status:
			if key != "power": check(actual.status[key] == status[key], "status duration/magnitude retained")
	return result

func _initialize() -> void:
	var frozen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FrozenPath))
	check(frozen.source_snapshot == "8daa519f2ea1a7dcc3f422b4df96ac81d65986b9", "approved baseline snapshot")
	var tiers := 0
	var normal_commands := 0
	var actors := 0
	for enemy: Dictionary in frozen.ordinary:
		for tier: Dictionary in enemy.tiers:
			tiers += 1
			normal_commands += tier.commands.size()
			for rank: String in ["normal", "elite"]:
				var source: Dictionary = tier.profiles[rank].duplicate(true)
				source.merge({"enemy_id":enemy.id, "biome_id":enemy.biome_id, "rank":rank}, true)
				var live := Profiles.resolve(enemy.id, int(tier.reference_level), rank)
				for key: String in tier.profiles[rank]: check(is_equal_approx(float(live[key]), float(source[key])) if source[key] is int or source[key] is float else live[key] == source[key], "frozen profile " + enemy.id + "/" + rank + "/" + key)
				var commands: Array = tier.commands.duplicate(true)
				if rank == "elite":
					if tier.elite_delta.has("replace"): commands = tier.elite_delta.replace.duplicate(true)
					else: commands.append_array(tier.elite_delta.append)
				var tokens: Array[String] = []
				for d in range(5):
					var actual := Target.ordinary_profile(source, d)
					actors += 1
					check(not actual.is_empty(), "ordinary profile " + enemy.id)
					if actual.is_empty(): continue
					check(Target.ordinary_profile(actual, d) == actual, "profile idempotence " + enemy.id)
					check(Target.ordinary_profile(actual, (d + 1) % 5) == Target.ordinary_profile(source, (d + 1) % 5), "difficulty rebase uses unrounded source")
					check(actual.enemy_level == source.enemy_level and actual.mechanic_tier == tier.tier, "no D/player level tracking")
					for key: String in Target.PROFILE_FLATS: check(actual[key] is int, "integer actor field " + key)
					tokens.append_array(_profile_tokens(actual))
					for command_data: Dictionary in commands: tokens.append_array(_command_tokens(command_data, actual))
				var fixture_id := "%s:T%d:%s" % [enemy.id, tier.tier, rank]
				check("|".join(tokens).sha256_text() == ORDINARY_HASHES[fixture_id], "Decimal frozen target " + fixture_id)
	check(tiers == 144 and normal_commands == 311, "all 144 tiers / 311 ordinary command positions")
	check(actors == 1440, "36 ordinary + 36 resolvable elites, four tiers, five D")
	var boss_variants := 0
	var boss_combinations := 0
	var boss_actions := 0
	var boss_profiles := 0
	for boss: Dictionary in frozen.bosses:
		var source: Dictionary = boss.stats.duplicate(true)
		source.merge({"enemy_id":boss.id, "boss_id":boss.id, "rank":"boss"}, true)
		var live := Bosses.resolve(boss.id, 0)
		for key: String in boss.stats: check(is_equal_approx(float(live[key]), float(source[key])) if source[key] is int or source[key] is float else live[key] == source[key], "frozen boss " + boss.id + "/" + key)
		var profiles: Array[Dictionary] = []
		for d in range(5):
			var actual := Target.boss_profile(source, d)
			profiles.append(actual)
			boss_profiles += 1
			check(actual.enemy_level == boss.base_level, "boss fixed chapter level all D")
			check(Target.boss_profile(actual, d) == actual, "boss no double scale")
			check(actual.damage == BOSS_ACTORS[boss.id][d][1] and actual.max_hp == BOSS_ACTORS[boss.id][d][0] and actual.armor == BOSS_ACTORS[boss.id][d][2] and actual.magic_resist == BOSS_ACTORS[boss.id][d][3], "all 20 boss actor targets")
		for action: Dictionary in boss.actions:
			boss_actions += 1
			boss_variants += action.variants.size()
			var tokens: Array[String] = []
			for variant: Dictionary in action.variants:
				for d in range(int(action.unlock_difficulty), 5):
					boss_combinations += 1
					var before := profiles[d].duplicate(true)
					tokens.append_array(_command_tokens(variant.command, profiles[d], int(variant.phase)))
					check(profiles[d] == before, "phase never multiplies actor A")
			check("|".join(tokens).sha256_text() == BOSS_HASHES[boss.id + ":" + action.id], "Decimal boss phase target " + boss.id + "/" + action.id)
	check(boss_actions == 40 and boss_variants == 103 and boss_combinations == 395 and boss_profiles == 20, "complete boss action/D/phase coverage")
	_test_levels_and_boundaries()
	_test_support_and_specials(frozen)
	print("NUMERICAL ENEMY TARGETS checks=", checks, " failures=", failures, " actors=",actors, " packets=",packet_count, " zero_commands=",zero_count," boss_combinations=",boss_combinations)
	quit(0 if failures.is_empty() else 1)

func _test_levels_and_boundaries() -> void:
	var previous_hp := 0
	var previous_damage := 0
	for chapter in range(1, 13):
		var levels := Target.chapter_levels(chapter, true)
		check(levels.zone_levels == [5 * (chapter - 1) + 1, 5 * (chapter - 1) + 3, 5 * chapter] and levels.boss_level == 5 * chapter, "fixed chapter/zone levels")
		check(levels.released == (chapter <= 4), "future interface explicit")
		check(Target.chapter_levels(chapter).is_empty() == (chapter > 4), "future chapters not enabled")
		var level := int(levels.boss_level)
		var reference_hp := Target._round_product([60, 1.0 + .055 * (level - 1), 1.35, 10, levels.hp_factor])
		var reference_damage := Target._round_product([14, 1.0 + .025 * (level - 1), 1.35, 10, levels.damage_factor])
		check(reference_hp == REFERENCE[chapter - 1][0] and reference_damage == REFERENCE[chapter - 1][2], "12-chapter normalized target D0")
		check(Target._round_product([60, 1.0 + .055 * (level - 1), 1.35, 10, levels.hp_factor, 4]) == REFERENCE[chapter - 1][1], "12-chapter normalized HP D4")
		check(Target._round_product([14, 1.0 + .025 * (level - 1), 1.35, 10, levels.damage_factor, 2.3]) == REFERENCE[chapter - 1][3], "12-chapter normalized A D4")
		check(reference_hp > previous_hp and reference_damage > previous_damage, "strict increasing fixed reference")
		previous_hp = reference_hp
		previous_damage = reference_damage
	var capped := Profiles.resolve("M08", 20, "elite")
	capped.armor = 200.0
	capped.magic_resist = 200.0
	capped.move_speed = 200.0
	var high := Target.ordinary_profile(capped, 4)
	check(high.armor == 320 and high.magic_resist == 400 and is_equal_approx(high.move_speed, 153.12), "normal caps before D in v2 units")
	check(Target.boss_profile(Bosses.resolve("BO01", 4), 4).is_empty(), "already-D boss without baseline rejected")
	var basic := Profiles.resolve("M01", 5, "elite")
	var from_d := Target.ordinary_profile(Difficulty.apply(basic, 4), 2)
	check(from_d.max_hp == Target.ordinary_profile(basic, 2).max_hp, "old ordinary preserved D0 base accepted")
	check(Target.ordinary_profile(basic, 4, 1) == basic, "legacy helper is detached no-op")
	check(Target.ordinary_profile({"enemy_id":"M37"}, 0).is_empty() and Target.boss_profile({"enemy_id":"BO05"}, 0).is_empty(), "no invented future actor IDs")
	var elites: Dictionary = {}
	for room in range(1, 25):
		for d in range(5):
			for zone in range(3):
				for wave: Array in Profiles.encounter_waves("L%02d" % room, zone, d):
					for member: Dictionary in wave:
						if member.rank == "elite": elites[member.enemy_id] = true
	check(elites.size() == 18, "18 naturally generated elite prototype identities retained")

func _test_support_and_specials(frozen: Dictionary) -> void:
	var profile := Target.ordinary_profile(Profiles.resolve("M34", 20), 4)
	var posture := Target.command({"kind":"counter", "auto_release":false, "damage_multiplier":1}, profile)
	check(posture.damage == 0, "M34 posture never damages")
	var melee := Target.command({"kind":"melee", "damage_multiplier":1}, profile)
	check(melee.damage > 0, "subsequent actual M34 melee damages")
	var rage := Target.command({"kind":"melee", "damage_multiplier":1}, profile, 1, 1.2)
	check(rage.damage == Target._round_product([profile.damage, 1.25, 1.2, 1.2]), "racial rage applied once to original full product")
	var caster := Target.boss_profile(Bosses.resolve("BO04", 0), 4)
	var drum := Target.command({"kind":"melee", "damage_multiplier":1.05 * 1.25}, caster, 3)
	check(drum.damage == Target._round_product([caster.damage, 1.05, 1.25, 1.3, 1.2]), "war drum already in raw coefficient applied once")
	check(Target.support_amount({"kind":"guard", "shield_ratio":.9}, 101) == 35, "support shield35% rounded")
	check(Target.support_amount({"kind":"heal", "heal_ratio":.8}, 101, 99) == 2, "support heal15% plus missing HP")
	check(Target.support_amount({"kind":"utility", "action":"socket_recharge", "guard_ratio":.1, "shield_ratio":.9}, 1000) == 100, "socket charge aliases do not add")
	var endpoints := Target.command({"kind":"guard", "mode":"cover", "anchor_health":1000, "cover_hp":1}, profile)
	check(endpoints.anchor_health == 800 and endpoints.cover_hp == 800, "single endpoint alias priority and800 cap")
	var pods := Target.command({"kind":"summon", "pod_health":100, "pod_break_armor_loss":2}, caster, 3)
	check(pods.pod_health == 1560 and pods.pod_break_armor_loss == 20 and pods.damage == 0, "pods uncapped, break armor20, summon0")
	var literal := Target.command({"kind":"ground_area", "damage_multiplier":1, "status":{"id":"corrosion", "power":7, "duration":3}}, profile)
	check(literal.status.power == 105 and Target.status_tick(literal.status) == 8, "explicit status power scales once and tick integer")
	check(Target.command({"kind":"heal", "amount":5.5}, profile).amount == 55, "absolute support amount scale-only")
	var defense := {"ruleset_version":2, "armor":1000, "magic_resist":500}
	check(Damage.resolve(1000, "physical", {}, defense).damage == 500, "defense uses1000 denominator")
	check(Damage.resolve(1000, "physical", {}, defense, {"armor_multiplier":.85}).damage == 541, "corrosion armor multiplier changes defense once")
	check(Damage.resolve(1000, "physical", {}, defense, {"post_defense_multiplier":1.35}).damage == 675, "ordinary weakpoint after defense once")
	check(Damage.resolve(1350, "physical", {}, defense).damage == 675, "boss weakpoint before defense once")
	check(Damage.resolve(1000, "true", {}, defense).damage == 1000, "true damage bypasses scaled defenses")
	var signatures: Dictionary = {}
	for enemy: Dictionary in frozen.ordinary:
		signatures[enemy.biome_id] = enemy.biome_skill
	check(Target._round_product([1001, signatures.B01.guard_ratio]) == 80 and signatures.B01.cooldown_seconds == 4 and signatures.B01.guard_seconds == 1.5, "construct ratio shield uses receiverHP; timing unscaled")
	var venom := Target._round_product([333, signatures.B02.status_power_ratio])
	check(venom == 183 and Target.status_tick({"id":"corrosion", "power":venom}) == 15 and signatures.B02.status_seconds == 1.8, "racial corrosion snapshots roundedQ power once")
	check(mini(Target._round_product([333, signatures.B03.heal_damage_ratio]), Target._round_product([1001, signatures.B03.heal_hp_cap])) == 60 and signatures.B03.cooldown_seconds == 3, "grave drain cappedHP ratio without skill rescale")
	check(signatures.B04.health_threshold == .5 and signatures.B04.damage_multiplier == 1.2 and signatures.B04.move_multiplier == 1.18, "rage threshold speed and independent damage factor retained")
	check(not frozen.is_empty(), "read-only frozen input retained")

# Golden hashes below cover full actor/packet/endpoint/status value sequences.
# Generated once from the checked-in frozen JSON with the target-book generator's
# Decimal ROUND_HALF_UP formulas, independent of this GDScript implementation.
const ORDINARY_HASHES := {
  "M01:T1:normal": "5aa12dbdb7811ed65e3c4436cc5d6b6960bb11142944c8830dd3dc4ce8ef481f",
  "M01:T1:elite": "5306c5bdeab1304a78611307d4ae33157fcac0395bc52e13cecc39a56c86cfde",
  "M01:T2:normal": "87e293257f05977e367c38529d58bf1e84fa779136472e06ff1e212d3a389cb6",
  "M01:T2:elite": "9a87b71b329db32ba4553a249570dd000cfb7dc2df20e4230159a23c3a3a2c3b",
  "M01:T3:normal": "6b37ad7aa52443dd0d4199def4c3b6fc43087a81930270ff3959001b8843aead",
  "M01:T3:elite": "aa00a80470d330920985e49101090d5fc11e2abc74564627352b5e123a828d07",
  "M01:T4:normal": "b244580ab0c16a1e077c0b31150ee1fcc04283b51de9b52118bf45509cd5a82a",
  "M01:T4:elite": "a8d0f3542d65cfdc4c66b7dc3a2772d3058b89f6698d1b2a7baa5f07bb5e67ed",
  "M02:T1:normal": "076618ef3a4b381b97117c09ea50ea7b17f1ad9a11abac02f5f30dcdf7cf5179",
  "M02:T1:elite": "3e311cfb1842d9b083066000a49cbd57831b603fc20132c88172ab05742f10d6",
  "M02:T2:normal": "c720b5ca615bbe9e66a4a1377236fe9953e2ea59484b491d18a4f97635ae10a9",
  "M02:T2:elite": "4b4565af50d2fa18e451a8a9cafecc297c191269dedebbce82897af7788936ae",
  "M02:T3:normal": "c6309a28f648c009e1462932bf633da754d4699f067073608f73afb51c21e242",
  "M02:T3:elite": "4649bd37a3f874ecd3178c2d313a10d139756aa1be066cb5aaed2cd359ab0de6",
  "M02:T4:normal": "2112f45e0289bc44649e50b74fe64cf914c74af1245b84d2514cc0d3afdc4244",
  "M02:T4:elite": "2fc1f4ae5391a0e0c3c871f0aaad16e880218648441d1f4a44b71055ae17d964",
  "M03:T1:normal": "d82107d4529bb533c14197dd6db4c1292ba9f17e3d1bb522fbf7a1428124d810",
  "M03:T1:elite": "a8ec2682fe6be936ff142c1977cd6445482f978eed0049bd0ff90f4bb4bac9da",
  "M03:T2:normal": "0f9457b423862e7c4f4bea68ea54acfb887457f32a7be14af434134da4939115",
  "M03:T2:elite": "3e25d66906ee1cb9c2ddb8fb1e0d2a38b1d94f351a5160d2e8b5bfb162030cea",
  "M03:T3:normal": "5b6b25090cdf4fee2408d5797d4e10e4820cb1301effacbb8a3f65aa49d83b9a",
  "M03:T3:elite": "4680f217b7eb4bc9e40134a1519a3cc23684d1991afea35182c0c973df981c50",
  "M03:T4:normal": "92a024e018fd5f58c3dea6c6f3e646577cc6c4cdbd12a46805aaced31f6b5dca",
  "M03:T4:elite": "98b26c4744bf6c635aca567dfdbb28dad05b2eb0bb92e28954d60f511641c778",
  "M04:T1:normal": "3a867c5a7b819d85d7da4f40011dcfe67542ca93619b2a84915315a75acb07d0",
  "M04:T1:elite": "bd47d075373bf90cd05b4f5bb30926d1dceae09b829bbd9f1dbeecf0f1a3a34a",
  "M04:T2:normal": "36d69bcb834603eb29588d09d34152c03cd5b57ce0aab90ff07cff48a1e5e59d",
  "M04:T2:elite": "1963d02cb3b74ad3445be83466e36fdbc009c9653651a2e7bde64b875e14b630",
  "M04:T3:normal": "3a2ba7015605b5e343c4dcf26f4f4e586e64e551071e0e0a286ab11ed0030226",
  "M04:T3:elite": "a126fd204a53fd01e80a5b34e7d2d15af72605df146f5056aa2899f0a1c95b05",
  "M04:T4:normal": "fa5b7e056a7aef08945b547877b83c8bd67111b76cc7352b4836ea793087b27e",
  "M04:T4:elite": "c5cfd2d17e19294fb5ac824037477c8fcb3de0a3aea403d4de2ff01dc94ca857",
  "M05:T1:normal": "076618ef3a4b381b97117c09ea50ea7b17f1ad9a11abac02f5f30dcdf7cf5179",
  "M05:T1:elite": "3e311cfb1842d9b083066000a49cbd57831b603fc20132c88172ab05742f10d6",
  "M05:T2:normal": "e2f774d5bd82eae2ce54163e4db079bd7103a7f97cae7ef2acb3d45956fd533e",
  "M05:T2:elite": "69a3711939273daa8e72ea72358fdbe12d6a174e58970a704aac515f48786aa6",
  "M05:T3:normal": "c6309a28f648c009e1462932bf633da754d4699f067073608f73afb51c21e242",
  "M05:T3:elite": "4649bd37a3f874ecd3178c2d313a10d139756aa1be066cb5aaed2cd359ab0de6",
  "M05:T4:normal": "2112f45e0289bc44649e50b74fe64cf914c74af1245b84d2514cc0d3afdc4244",
  "M05:T4:elite": "2fc1f4ae5391a0e0c3c871f0aaad16e880218648441d1f4a44b71055ae17d964",
  "M06:T1:normal": "1a19aa664808732259908390531aac54341453ac9aede3912404e0af8e1bd1e6",
  "M06:T1:elite": "a0f29ef0542376052e4f99a95300d9381e0cc116871dbfc5237131a0f37786f5",
  "M06:T2:normal": "d9e678d4378b6e404876def0611ceb7d33308f8c1aeee56bcc564ca178385cf2",
  "M06:T2:elite": "c3e1b996c80f99e0c6c90978e784486d3f195b53ad37e776db9c073c17c352f8",
  "M06:T3:normal": "1891a0f2d87e9daa3a7cc2537ca3c4af78af6311b9a5848440c6e645ebf57a91",
  "M06:T3:elite": "c7bc604b336ffdaa46b871c1cd708a8656e61e6fb5b3cbffab2c9b00a58bb2bf",
  "M06:T4:normal": "82a1b3bff03bdb7db0cdf2ae749451e6b9266958aeb0045dfc780cbe0d8cb804",
  "M06:T4:elite": "5a2b18053809df56df8db97d9ee244f6580a2e840762ac4057616382d3ef516e",
  "M07:T1:normal": "5e54f3a985f014027d8115fb9ba71cd8864f1bce3b9c1cb50aebb9ac279d6ec0",
  "M07:T1:elite": "d8b06aa9eb424bda037e3d9cf708ccf0f2d69d35f4bd3f19d4593cda80ea27ec",
  "M07:T2:normal": "51466b24e6b6c66e9f775c72c5a9ced3c2ba55e0e865983f0d6fcd7150e36a37",
  "M07:T2:elite": "7228821efd543ee4101f2a16f4d92ed9949d0a5c2110611ce120c46fb3c375c6",
  "M07:T3:normal": "a58577d2fc03aa1c92ac7c09449da20993cac4d1576779c9772512c7cfe53548",
  "M07:T3:elite": "d05f059e73fb4bf5184a4d0ff42fa154746a9e540a3f532701936e7b5685acaf",
  "M07:T4:normal": "2b48842ebc85b0626331aa8ad8765c01303267b3251fa144d8ba922dedac08f3",
  "M07:T4:elite": "89f998da38ebbdbe9079eb1444b20aed91487c0808ae1c55166e944e8b63b9fd",
  "M08:T1:normal": "f16e46b697883c723a21bb168754ad9dfb1c9071e2dd6d12bb0fca0ba79d5bd4",
  "M08:T1:elite": "1481756ecf1f4f6ecd8a368ce3194dc5c8329f84b959e8b86504e44313e3ffa4",
  "M08:T2:normal": "4cb8f02e4af9ee512c948ee915b6e54aaa405178419489c8c18ea2541bf4455e",
  "M08:T2:elite": "c2519f3c885da736f92ce5f77e6720c1133c0840e25ef98cbbd54345990d69e9",
  "M08:T3:normal": "8610003dd5d7be487c48817a2c8aecb1cae01ddb940b7505d7efd9d71e34f97e",
  "M08:T3:elite": "0b7f108c322db11bbef956d9d33c6323e5ab192e39a9d6f10ba163deacf49b30",
  "M08:T4:normal": "3b31d4d5efe8ab2006f2ad0dc605704a49219ce542b9736034cf2a86d52d2981",
  "M08:T4:elite": "ae7ab80292bd83c3bf1b2bdd00a28c12151814637a675fa5f60583340f2aced4",
  "M09:T1:normal": "f4b56288fb0e08b9713b30223ac0ab0956c8a792977a8e5e828edb204c3cbdc6",
  "M09:T1:elite": "d0263b859123c3c8d45b8c36b08322052b9e3120ba11457cf82cacc24d34cb39",
  "M09:T2:normal": "52ecd94af907d1a8b6eccaca20c92b91687049a70782156c842ae3152abefd4c",
  "M09:T2:elite": "8614a14251273a35b3200e7c213fca4db96fb2720b70efd532aa2beb0bfe4a02",
  "M09:T3:normal": "27ca2f9af07834bc9c42044ebf52d78538f620d99412960755883a0a20f3dc8b",
  "M09:T3:elite": "f180b4b5a78a3c6f5bcfa67eac88f4c21e035016034ee2f2b14e0a8a8a592ba7",
  "M09:T4:normal": "ec1d79f580c95d0365353712890f9693109356737bdfd4a0e3d61635e4a7d0fd",
  "M09:T4:elite": "a88e4524cd5124e383b747bee6fdd4e277144e6232faa0dd5869490580e1bbb0",
  "M10:T1:normal": "55b5fa86f09e773738de5776e7cf00142111ff97f61442fc2a6c662cad962513",
  "M10:T1:elite": "704fa2d453492f6403920205c59de9caace85315e3469e82d37f388bdac3fabe",
  "M10:T2:normal": "a8f38843b91f515adbc4b08fab2f19563f624d10be23fa8ca2b82bb5acf322e0",
  "M10:T2:elite": "0388d8931468a197d6bd43d064fe7d80254761400893207f743787894c5931cb",
  "M10:T3:normal": "cf30efd6b388ebf7c0e3d3de31a59b2223e5e49157a5c8a35dced041d61da588",
  "M10:T3:elite": "81a7488a58556ec99b0c1788e0bd68e8ec769e6bee12d5eef58da8d1b464f051",
  "M10:T4:normal": "8f4870144ed58b6ef19c1d3e25feb41a7b5c65996e6281521121954568880276",
  "M10:T4:elite": "701f0fae115ebab03c07be3cca3e19b348b43fd12ce1494d4bb180ef37ee5c28",
  "M11:T1:normal": "3a0671435db9f0002ceba804e3aba141952be3a69aaa4cdff1260a90c4d526e3",
  "M11:T1:elite": "1663245678fd9ec31cbaf4f5ff5599e9c4a0679847a79a5f17a90084fdb38518",
  "M11:T2:normal": "2c9d74154fcc02ae0b028c6d65fa88df3adddf17cd8377366e50f5ac16eee02b",
  "M11:T2:elite": "cbab35fe0117165a37189cdf9f4f5a00dfd5106192740746400401c9eab2ef2d",
  "M11:T3:normal": "13034cdbc93a2ff3bfab977a3d0e1a805ec70bf89067cf76c819b7b4bff93870",
  "M11:T3:elite": "b3e406d25776f31771a6a176b9b042e64305424a1c7e54ad4ed3d682376d1568",
  "M11:T4:normal": "20dde09f5abcf482e587acc17eb08f8206b6a2deb92af19a2390bfd1b6c15914",
  "M11:T4:elite": "32e9587ccef59f7eb3323fd528248d390fb345b4e14853e206250a46d643f36d",
  "M12:T1:normal": "366f0f591d534de4379ccd61061fc6762ef80bee93052fe06a78e6940c92fc8f",
  "M12:T1:elite": "6b281daf80bc11e7ddee4d40233b06ac8c241bd086f8fb013cc05e9d1e597194",
  "M12:T2:normal": "af7be97ae30b6dedc75a56ebc99d02571112f30a082bd26c6af41543691366f6",
  "M12:T2:elite": "f7c716886274c3a58da2b98760b0726913dc7a9724794d18df81cc661df753f8",
  "M12:T3:normal": "ecd4de25469da02ab823f436d5b05dd7951fdbd5029d9021ec941b9a98083b91",
  "M12:T3:elite": "e4dfe472970286fa78c3bd8c5dd3879f78a457a3e3c8d7ae69536cc9fe8a850d",
  "M12:T4:normal": "53570225e0eb6b297e7440df2cd3cfc9c3ccf3720d65c0460ee9d1a1cc732bb4",
  "M12:T4:elite": "f451e430d61a1713216071777cd5e35281d4a8020e35ce637b23ecdc8e49cdf3",
  "M13:T1:normal": "55ef04ccb5c92ba1229d01d4f86a5136318c6d1760f9bfdea4d9f864343dd2d4",
  "M13:T1:elite": "20df16e52ba2d7de96d7b1820a9406383837a59035f04fd28de5b751cdf0d045",
  "M13:T2:normal": "e2e2c608a241f114938eb0145c67ed0b8129cd97189826f1e53d9c63bdfc3329",
  "M13:T2:elite": "f1202a050ed33daa24ee0efe09502ddc7c91f913d9b8fd661af2a696fb8cc947",
  "M13:T3:normal": "4d5044d733a2171fb5d4986bfdaa4742de2c07e72cfbd7e64b54aeda52ba3b9d",
  "M13:T3:elite": "6e72778c65752a9812eafb455277f84a9ce47199b9ffe18ba9a966a4bebbcdca",
  "M13:T4:normal": "51cede0407144e8b21aea17d93516318591ce6f315470f3ce4a9c32513f7d9c3",
  "M13:T4:elite": "65ab1dfe0bb75f19f57d11866dd61a62a647d9f0a9f2eb375747a2101e5ee657",
  "M14:T1:normal": "6e97e12c060acc6d6f090872a9035501edbc7e0a888d5c62aae2dafe01894a31",
  "M14:T1:elite": "40edba86a76e794271344f7cebace9645aa0d5283823369c7be74c183ad728c2",
  "M14:T2:normal": "a79969d4939723ea8f08ffb5b531981220fb74a2bba393a50c28834f549a971d",
  "M14:T2:elite": "f2db3575456a9f3bffaef54ddb5bef440ed5646ca287744058c463d75f83a83e",
  "M14:T3:normal": "23eaf9bca3f66e5fcb354163f1d4415e949034778872d703addcc89cda56f70d",
  "M14:T3:elite": "963f131ee0a78ba56e08179172d7c81f8f5f01b028e81faf0e5385872dfdd6d1",
  "M14:T4:normal": "bfe1ac3c05b3369d691998624124f10b5639e373305bc93ec942005e49e19785",
  "M14:T4:elite": "d9af4820247bad69775a68d652d6ae46fd556fe47e3f252860f82c1a698e2c87",
  "M15:T1:normal": "ce0628c9fc8b7eba6d37ec0760b5e0793a1227e462394c9fb4e5d577831d6fb5",
  "M15:T1:elite": "3737c0e07bb8d8b2525b803fa870ac326ba725a77d97ae8344f31ee80458851a",
  "M15:T2:normal": "8d6e2259ea0302965d9b8b859ddf7722f7d9263625992e5deff2a8e7aee268b6",
  "M15:T2:elite": "3f1b6e5d886ac0827b170cab48de48644285873c6e37f31314fb4d3031f59ddb",
  "M15:T3:normal": "8ec298f861cdfed973b0ffbd4a7f8bad74b9913c504ed54ab14642ef17c20343",
  "M15:T3:elite": "adebeccb21122e30ddf4b325b274d7d74b9ce1ff37897f773961c198ddb69de5",
  "M15:T4:normal": "d21c6b37349c43d08baa34d77199ca384cabf14b3a8d5757ea625eb9d571917c",
  "M15:T4:elite": "8f9e2ff45effba37dbe6b641d78163b0cca825d65e668c7594935c8a3b40f2fb",
  "M16:T1:normal": "a79db97e079b706054ed2446d71e5aad8cf5be2f24714899a37aca5dc508777a",
  "M16:T1:elite": "b33413cc7a0cde760206b5694d54851ad68f312c98ce6c15bddda39c39de8d35",
  "M16:T2:normal": "205d58a7358cf0f2d4acd92a1414b7f8cdd994a9a82782e30a759bddc27c3b0d",
  "M16:T2:elite": "f84ebf8fdc48faba5a49882d8dc55211b55a87d4a4824d402b674a31fd6f06fb",
  "M16:T3:normal": "0489fee8e0472245a4f1b079073eadd71682f9c166e6481d660ec2a06e45f792",
  "M16:T3:elite": "d7e502674c6e62b48b4f9e5967cb96e8f4a3960122b21ec68a5dc77e2cacd2f6",
  "M16:T4:normal": "ad11a94429b7b21eb28870d9fa98431ff551a3225b740e2a4971e2032a9b2571",
  "M16:T4:elite": "7141a8247af877ee0147d24d641948b95ddaf828116989680b908ccde1b752f7",
  "M17:T1:normal": "0a43c388e8e7c05cbc8b8292ece609460ada4c978994ff0bcb0ca82893f84298",
  "M17:T1:elite": "a95341b81d99e067e9c186b059b4a36d0b2de19d496541c6783d679e0235aeb4",
  "M17:T2:normal": "ef13b031b57b2acbd59f78cef34d48da651e3c3a41ee527704b159e5e413169e",
  "M17:T2:elite": "03e6c975fc87ef2ad32afaf44a84095d641f5f8c5a2526c1db5cb980b7c16866",
  "M17:T3:normal": "b6f0a38e6c92762807f9a3352eecaf9fdae51345f4a26ea84d207fd8a3e8c411",
  "M17:T3:elite": "feacfa1dfddba1354c798542fd1ac6717d7f0495f11dadab9a64131d5ee389db",
  "M17:T4:normal": "a7aee632f6c5ddc26f51f8c3522d50ce8d2d909e924bc80000c4a18753a5af1f",
  "M17:T4:elite": "a22537fabaa8663627655f1c312fff1032839ba7a4b6e35e03ddfabd9cda0bd2",
  "M18:T1:normal": "882258e8799fe7a0158ed54ce1dbada8ce6a58de3d18c162b69903fe58254bb9",
  "M18:T1:elite": "7b089710efce1d6443df9960e2b13f28131e54469b5b4984705490c87995994f",
  "M18:T2:normal": "2c40857bfd70be2c7b3fe56ecd313a2d4c8fcc6429027c3e4b82ef2c634f4277",
  "M18:T2:elite": "1dc07b163b4785506d1035c965943e579592d55760e40c2dd630f94547c9c00a",
  "M18:T3:normal": "86f478a3a7cf3d15a85ea330505d6261a1f319144ebb9b6631d7aab603d14600",
  "M18:T3:elite": "3f643563041f8837aee1c657be7502a6477a79cfa68a1e541ba789b5d1e9a2ff",
  "M18:T4:normal": "6f60be7189405f660754f8c83cf786496c8c7d747c23c9fcd78a20c45d503c8b",
  "M18:T4:elite": "b6139f76126d197007a65dcb2f04f7c4dc30ffee737b085da54c8cc1e7fa714e",
  "M19:T1:normal": "1421ad8b9da4b5e7ff564cf4c21fde9f180ed4e4430012f5391642fac75f11b9",
  "M19:T1:elite": "1c2414b90adbc4318c09f3031a8d3dcadc24fe9e5195dcbdc53f125a40f76837",
  "M19:T2:normal": "f314feb1dcc67100be3a0fbfbefe6290cabb25618c212305cd5598811bcee58a",
  "M19:T2:elite": "6365424e79660e1352bb31c42753e72ed25afe4c07d5baa2c21db5055ac896c6",
  "M19:T3:normal": "f0fd808d6cf239a2f2ad0f13e2186c5530600a68e98de6e7a69b90c2b060ae47",
  "M19:T3:elite": "d66d4bd66d91042a21a49703b9649cfbb9b66d3c09757b9d2e6d4acc07a0e7b6",
  "M19:T4:normal": "4145f806adf7aafff2167dfc85810afe9da5e701f42f01653884bd6ec6c68f75",
  "M19:T4:elite": "0715dbd5955d8e10223c346f651dacc07aa5404c48c4575dbf709d16287f5a41",
  "M20:T1:normal": "34fcd08e49b6ab3cf731f04bde8f5eadc4657661dbd9fd6cc06517ef60aa0a07",
  "M20:T1:elite": "aae68cb62eddf6a41fc6c26d63a0f30e115af80012a8ac6e9dd97fea380f2325",
  "M20:T2:normal": "8f42561bb30262e96b57087f28a8ac24b82dd3c7ece22b5637967027d7e424b4",
  "M20:T2:elite": "0adb660ba3254256191a986cbb647d5166e182b05083436357ef4fd819764723",
  "M20:T3:normal": "6cb3179c45fb4d1cb9e621e824a2c3c4ffa73f83424fff31f5c2920ac92fd36c",
  "M20:T3:elite": "60d713f61a299752eaa73d260adcb8d005a5679020ebffa4ce74ffe299154e22",
  "M20:T4:normal": "b769c62f12cda73c1a64db7f48cb21f516325177d074986eb5901373b7d2f3ea",
  "M20:T4:elite": "99f4296ac6ca6be70993d8bcd2fd5ff6a741880ffbe95ff53315454ef01e884c",
  "M21:T1:normal": "aa432a24cacbd9fe93e60b11ad81d17799cc1aef8a77a9669681303156ee1699",
  "M21:T1:elite": "accddf34f65a398b75cf802e3a028d6cecf30df49d79a1750c3e3a9fb3413d43",
  "M21:T2:normal": "b6e437fa97e08467a7d8b4634167d73422fa33b46d4b76c5397605298d551594",
  "M21:T2:elite": "b7892c4464c4332a1223732dffe6f1515bdfe4118da4e2d9f040f48fe65c2ffc",
  "M21:T3:normal": "be187cca231a15024180d99d1c0478949c0d70df3de6f5235442ee5c61c0e905",
  "M21:T3:elite": "330f235622073d9c49b86e276ef6a39a07975657ceb1724a2445804856a9a370",
  "M21:T4:normal": "3a081d76faf28914b3c27d3070dc1cb2b8d18963221f97a5f43f3007a3b90d50",
  "M21:T4:elite": "da7d72a8c5b2a2d97d469cebf04cc793d84956fbd85e7a695324de195e1c98bc",
  "M22:T1:normal": "7269154ecfc95b66f1f2fabbee54a404f654a4e5101d47211af31d9838a49ca4",
  "M22:T1:elite": "8476f8ab4d4ab24c0db0ee8c42cd7dae380e32e89c09fa008b2d888ec2b8ff19",
  "M22:T2:normal": "0a49b071697d2ec07c77f9e77e91c90d1d30f2ac68e7e96f6a458c2bfee6226c",
  "M22:T2:elite": "1b52b76a4b679de31deb2a7f84d9a7c9ff381c8de33be3c0b9843b035fb770fa",
  "M22:T3:normal": "1e939d4434cd31252abb19e2b108797627eaa43d8350a219b449fa20d4695bf3",
  "M22:T3:elite": "7f4a85dd542f72d55cf61a7e2d8a086ee6fd51b136a740a91f211291bb534597",
  "M22:T4:normal": "2409d3064c20363ff6b145745e7a3ebaabd974c562c5158fdc4329ef21ad9b3c",
  "M22:T4:elite": "34f72ba96c5b4ca1644bcd667cf147696cd9dd0fd743a41a097a966d5597a1f3",
  "M23:T1:normal": "9b833659dbfe87afd76a76df6b39638dcae6679d99429a4171da163bb61684d8",
  "M23:T1:elite": "5008b507fc63add2306e520318d66d036e5d5837b53bfe247362b2ceacfc5eeb",
  "M23:T2:normal": "80620a9b1d26d1f6e3b9f74bd80b382466e2e3fbf8e1a1cf141a210ebc3673b7",
  "M23:T2:elite": "ede4f328c55dbda1232ced2280b296793f6c1795443b6f444e469870fc7dcb95",
  "M23:T3:normal": "106ee85b943e9db983de3872837967f184b1de317b2939e339669f213e120525",
  "M23:T3:elite": "ae8d17afe9139131eaab8c5752941a6c87b95f140e318ba0cfd64abe0a992fdd",
  "M23:T4:normal": "b1af1377ad85be0a92f3dcdd56b33db05c766aa2baf4d97de92e9cbe5f81f406",
  "M23:T4:elite": "9eb6f2ff859be570f1af4de86549623a8ebb17ad8e85d0434d8a6ac05c5edb5b",
  "M24:T1:normal": "52713c2070edc875fb6d7ea0cc357451251a8c67760de3dae9511fb5fcfedf54",
  "M24:T1:elite": "9514f41ab987afc363e950d2c09195f078f6a7e7c3a3a1c5a48bd43193b4f8a8",
  "M24:T2:normal": "63f870eebf10c8f412d83c5ff76542042d010ea607c4762bbae76afe2b607097",
  "M24:T2:elite": "159bf45228c0d646fe6de69b9e8c2be0ad0fbaa8f1f8890dce913e142e47a782",
  "M24:T3:normal": "9f2088179455aae94de64f11bacd1cd763727101e36a69d9494c100098465756",
  "M24:T3:elite": "9d076c87fcaa1f6d0d1929a44d405a6fff0313d5fb2f461de7ef9817b79b88c2",
  "M24:T4:normal": "b49bb00a4df04ac8afe544968595120ef56ef0881cfe44c6bd50c2af75ed1bdf",
  "M24:T4:elite": "a5b7e91c1a8f0471a2dbecd997d13e9bf62bb540502cc1c28005da0201de8619",
  "M25:T1:normal": "84e168026f14c38200cd3fbb9b04cda0f669d9f1727230866419da70d6801d6a",
  "M25:T1:elite": "7f74fd523f1bc7d4dbd200d346bf001e4b2e2b991b6de7e02193532a807a3d21",
  "M25:T2:normal": "321c7d8ac189231bd73cd439792cb56f6569649c42f41d65075f5c928101adfe",
  "M25:T2:elite": "ac88eb12d57825e4d7890c3c3b58d6d75303e8c660da208263954069a744fe22",
  "M25:T3:normal": "992c75eb519034e27567ab206a4a63f94aaae24fabb6c869a458feead445236c",
  "M25:T3:elite": "3a3964c39062fc78fd0ce370a346f1abe7323378b96c1720194b5d5c05e118f5",
  "M25:T4:normal": "50944eeec14b511bda3bf3d6b42f0da597992d319b8daf00e3c113380f5da571",
  "M25:T4:elite": "202a3cd4cc2acbb29e092684007939e3c119d6bdf4b32e2fd32183119316537e",
  "M26:T1:normal": "ee62bca03c6d245006b4f499ce45192a8234cb3076086f952c003a103795a92e",
  "M26:T1:elite": "38dfbb0a405e83a3a04d382d1169101facce42975efc6077f72386421006a3e7",
  "M26:T2:normal": "ac98d0759b03c5547d87a54884cf16814e5d4283e16a0e90e010d181f0fdcca5",
  "M26:T2:elite": "143432b9d2413510e06ba56d102a404566a2a9baf3c040327c25658492919ec8",
  "M26:T3:normal": "df18ced5ec023a4738e46c783f338197c44c650f9afcba8ea0b5c76a02ef7fca",
  "M26:T3:elite": "877d9d8b0b6fa0f8e538ccf329ee2db014435541ce85761b46f3076febd3460b",
  "M26:T4:normal": "2bdf530869d3dcc638919bc4f5ff17879219d334b2c28b3799a4c04070d2c785",
  "M26:T4:elite": "4c2319363c216304fc1c3263ba2923edc03c17c82cbd06f6ffd800a91984a797",
  "M27:T1:normal": "6bfedd87ff7b191d12da9e00b39f361f5cb56565c75d442d3ff0b4da2677fac7",
  "M27:T1:elite": "ebc9c40a5fddc98c9150a72e064caa4a50b95697e75ec4c8460cc19125686d96",
  "M27:T2:normal": "d9e1a8712020c9e3f194d50d4d62d6058a0e53c3ea947752bf5a991086e559d3",
  "M27:T2:elite": "be1691e496cf43b5469261177c4741bd2cdab4a1ebc7e7a2a3e10cdb87d07d59",
  "M27:T3:normal": "f16c5576455677acf8a1376a4313e919a5b1f21f291733a0348e9a1bb47a2d76",
  "M27:T3:elite": "7e1a2bfe51be2ecdd77eae7e3e0989b173aee186d0aa29745ffe4b1afcd860b2",
  "M27:T4:normal": "41e6f3d33bfa5464c4e77a2d583ba0c563735b0783a25fdf265a251ee1ef470c",
  "M27:T4:elite": "fd7648db161f7e6820ec45ec66d625d5ba488d6a995bfa338052b08b1d4fd575",
  "M28:T1:normal": "b61c513eb0d67c6632871696b20cabdb2215813fee3e404ca4f6569caee8c4a9",
  "M28:T1:elite": "de9785ae226e5e20ae0b610c8a6aabb1b75d7f3f2e62842faec20ea3d08d3c0b",
  "M28:T2:normal": "5efa0c43dd100f68c91b682063e5dfa7fa8f640c4c56ee5bcd4a8c2ec4c968a8",
  "M28:T2:elite": "463fbac922974f9bc5a31cc158b66a87bcd4f47e4d0e10968ee81fd67f9ba8f4",
  "M28:T3:normal": "f187653361e29b3d02e2eba284a4ea6263e1ef605d8fe605c8cedf395d72fd0a",
  "M28:T3:elite": "fd3242c13ae6b2dc1974f1ed081437b03489d82239168e170e1448f0c7ca077d",
  "M28:T4:normal": "4708617d4bd3b5167deea7d05820ece1c66d8cfb467b7cc74caa7292e4c6ee72",
  "M28:T4:elite": "030e94beb0b7833e8ac6459c741179a76dc404aab15146859e71d5e9c6c1e95f",
  "M29:T1:normal": "5fcbee2291bfe881bda0b78122a8636f9939eb2d84269d15628114de1c209a8e",
  "M29:T1:elite": "4da099da5033a0fe5cdbfccca6255def181acd0f6aa1d62e34afb870775445cc",
  "M29:T2:normal": "d28093e68809439d6013f4dd2e852a6ec67ebcc35d58315035565126ae8cd42c",
  "M29:T2:elite": "9097c9288a277dd2ff9f77bbf78359939f252a880a2d13b2badda939c3648627",
  "M29:T3:normal": "60e70dc511eb46bd4eed11aacbbf4bfb02e28a207503c6c17078a34ecc6f61c7",
  "M29:T3:elite": "26086fbe37bccd5c2ce7862208978320e75757ad216a581fd886a3c26146ab8d",
  "M29:T4:normal": "15ed5676f2fc76ae23920219dbe8385812cdf44af8742dbcb6aad16ac982886b",
  "M29:T4:elite": "0a24c7f27f0af3a6b247e0f6f80b1c984fc76fc271b1d4c2f562d4296c5ce95b",
  "M30:T1:normal": "0c3bb9951c8259f08d0742376c22aa0a2cfee15ab61f7511ba0264e627029eed",
  "M30:T1:elite": "c34854e7c775910b8a7f8f5e33cb9929671502285686099f43fc77fea6a0641d",
  "M30:T2:normal": "84db1840bd8eaa77a9bee3bbfadf369e32866cf68364da394f1732a10d344932",
  "M30:T2:elite": "dcc25fe20924294c887637403737ece7abd863ea3626e3ebe373f30bf2299f23",
  "M30:T3:normal": "e047e67f61a6dab7f150acb79bd2cd576c6e2e0338d6faa15b542fdc77a9a582",
  "M30:T3:elite": "23b58cb3acfa41c645f6f5ddbb07f63c6d293af19aedfd4b725830ba2613369c",
  "M30:T4:normal": "8a993ae88134d5315108bc2249882ad1ac126eb476dbedafa85f81ee7ade5aa8",
  "M30:T4:elite": "07c84d9f5bb3d372d22d85217a118b741f0add333e33eef04ff3d3ca90e243ba",
  "M31:T1:normal": "c4a2ef82d92b11b7a5b2a6ee96c467dab684870291f1c381156bb9b7d995a73e",
  "M31:T1:elite": "5b653f9b38a182ad7daa8cdc631cd36254512adc9a596abc55674ed3a34ba9ee",
  "M31:T2:normal": "0318530bd62230d3157715055fca4edce90f071542fbd91a50224cd0ab6c7d5e",
  "M31:T2:elite": "e1aed9264a357ea577803fd02d78a9fc27c7fa66bd359760bab3a5de92838bf2",
  "M31:T3:normal": "b0c0dddff969b37c59fc675ac1d9a06343426d470aa829756771e1879455ed1d",
  "M31:T3:elite": "9217c14f745d6c3c18eeaec78a6f46b537b54188a9420e6d78577befaa268613",
  "M31:T4:normal": "5d4c4ae03e78a18a6a7d36b708c9362a14a5cdf0d0c78ea0e0dc3822eb5bcff6",
  "M31:T4:elite": "9a2f12c03b45da6d1d0cb54ff6b8aef6e446fa3cfb7e1248b899838b9c0fe312",
  "M32:T1:normal": "1881e3f961f1cc1af2c2df51ba81f697099f2e6050d847d6b49b90433d55ffae",
  "M32:T1:elite": "5d7a381377eef387366686f9ca6d28b2a90695fcf4d8b3039a5e386ef6a165de",
  "M32:T2:normal": "88c75ad72ed2acc5efb2216ef9b2bd9d816673dfc7428e88156c5d650d6996e1",
  "M32:T2:elite": "6253b34be2dd3ad4e2053a4f5545c63d561c83d047693cc68b4744fb7ab53148",
  "M32:T3:normal": "89dc588eaa03fd62bfdb90279a06b77444d4439c6bbc9a651e851375723d7680",
  "M32:T3:elite": "ea158e97e6abc6c83a152997a13e7873580720f1ad4fc5f0a9fecd0afc80bc8e",
  "M32:T4:normal": "9e3f930839516373c35e9dd891395b61c2ecd8f3484c512ee39a61779cc01656",
  "M32:T4:elite": "317a95fd1207bda7f58db519229114fc9b697451eb6e374b52afcb388ae51996",
  "M33:T1:normal": "9a7b6ee2a00b4c6b56952e0118047c9557c29f6d9b1b467474a07e8468715c0b",
  "M33:T1:elite": "523abcf7a5507bd203aa75abf8efd596f04b8f3b4ca6dc99e009cff137400c25",
  "M33:T2:normal": "b8f85b6db5040162e3c0acbc7c87edaa1775cdb8c4b0c84438efaf4cc3fa7aad",
  "M33:T2:elite": "328686b39979272b0c5a9d2d6863a56ad8054318613850deda75fdcd43cec664",
  "M33:T3:normal": "b54eb6a7f51561bab8400ba2fd93d556d06f1d4247197ba71706e640dc59d7d0",
  "M33:T3:elite": "6a21d87469c1be72967182e2817c3b9979bf91f506ba5edf6875d4eb285b1ac5",
  "M33:T4:normal": "fcb6646492b9acabd2a788c489f38c80e3a749f4b26cea60ddff3ed574ab643e",
  "M33:T4:elite": "cc505e4ec3a28385e0162b3bfe2f1c22b324cc3201723201f96a03ee2b435390",
  "M34:T1:normal": "3d11d4755301a7a148530f94012912359509878dc95afc2cfb953b2a66b540fa",
  "M34:T1:elite": "e0f940d82bdf70bfa810274e04fc49f21971453905f54d8e99d8216fb0873622",
  "M34:T2:normal": "7ec5df774b184b11a43298f33f8690aa47c41b2eac74408ad60c23e5be07328f",
  "M34:T2:elite": "99c75386f44f2cd55964922186e023fec6879110e9b9512a3151d5e1c45c9cab",
  "M34:T3:normal": "1e31d1a305892cbd3ef3e5be12fa4dd86164cc9646b4b432d826ef3cd9656eae",
  "M34:T3:elite": "cbd939fa9d02dff9dab1977e764630f7fd00b181aa7c371c3cb1eb418b527a1f",
  "M34:T4:normal": "ecd0528205e34ecd967f9c6e9ea0c36fa735e7951cadd723349ef23af8b57a1f",
  "M34:T4:elite": "d1a56ed4a45b1e7765ffa71a60f683028257ee9b85da2833e3fb2a2b51be8474",
  "M35:T1:normal": "bfb4c1d1ce27e4c7a272aa070a2d76640afe69b6fce6acc22b13ceb0d6255ab2",
  "M35:T1:elite": "6968736902df2231c7bfcc3db2fae9f6e3c1f2419af579f0696f534a6e5c55a2",
  "M35:T2:normal": "3a1468e81d22d7f577737ae282e0d885b856f26a55b1dd1c93b5526ab7ff2222",
  "M35:T2:elite": "492856ea0f08f4ef149c58e21df5d4e0ae03946e9fbc5d48c59cb9c5e1c9fb6d",
  "M35:T3:normal": "8825318176dd81bfd6a289f756b3550bcbefd297f77e0ca3bdaeb62ff97c0223",
  "M35:T3:elite": "1438cd594512533e1b8cfde70faaa134fb44d45c2a8b5bb0355d85770a540a4d",
  "M35:T4:normal": "c27786a8700f16725e658a0400cba4bc169751342518c1be06b1b4279e8aaab6",
  "M35:T4:elite": "1840455b85d232860bb4112e7c78d257c6dd3105bbf83c1a366a069cbc120e17",
  "M36:T1:normal": "27ebfe67cfbe7591212f76ea1f1076ff6ac3202886525e85f2a687f69474473a",
  "M36:T1:elite": "05dc4f8af1efa3ade2d81f1f8b0c132f0ce0a14f808be0b8ef7661ed1f988a3e",
  "M36:T2:normal": "7a9de683423c8759731bf078c56d2e802ff0326594db31369da44394b9b5421d",
  "M36:T2:elite": "7c5501cd70689ef6e79fe1d485993c72c9e08a1582bac42112aa8b0eb77d3d16",
  "M36:T3:normal": "e59c006152536628086896f13a112ba7bb09735eb6023421147cb6e425430e2e",
  "M36:T3:elite": "14e2d981b72fddc9b11f7da8c8078e0136e08d6d02b854c087e5e6b6356056f8",
  "M36:T4:normal": "8ce298fee5c84f95a5c77ff94ce6f08954f11cdb2cff25d0bd13ea7aedbfa677",
  "M36:T4:elite": "388adef526b1d014fe630e536115dee4ed1e0e616128e40c0a0f5e4cbb09f578"
}
const BOSS_HASHES := {
  "BO01:hammer_fan": "be18ec7fcdffeddb9543840f853ae0fa2d5af3b4ee28983c1392f7b7c4eca3d8",
  "BO01:ladle_drag": "a18b0b1340208281e89f81d402c74903e3ee13e144fcf9479647ddfabec2718f",
  "BO01:solar_cross": "e7f819d2a0e5f91a7256dc70533546a8a12c64d059865f54426746eec635f151",
  "BO01:prism_fan": "5cebcd3279e6f0284a7c75f8972d2c3d7d47aa532628822e16e783adf08fe730",
  "BO01:solar_mines": "a8b7855111a5ab3f727e04c3b468bdbeab8dcff5273d923b7ed78ebe52e911d8",
  "BO01:gear_dash": "da3c2c4e87372369742ba2421f913d0ba7a69d4e1633681b092e6286ec1cbfae",
  "BO01:eclipse_ring": "9630959cb1ca829db6887d324056449a4d5b1b1ff2881eca2edef9438f6aa389",
  "BO01:slag_lane": "f5afbe0672492372cab7e05ae77fe4a24b50de1f38ad2d854329728c3ffd9d52",
  "BO01:back_heat": "27112bf1841aeb9cf6afa31214d44234570c1d1751a072ef48d74897b8c67d65",
  "BO02:root_fork": "0cb36f6ad13b87e66f565ae3d5c1b54d5584a662ed4fcaf5a3a36be8e45b5ebe",
  "BO02:spore_pod": "ca1f40818f3f85cc6674a7e7b8b97a922670fc800d6881e57c585c86a9f51e04",
  "BO02:brood_eggs": "d5571d028032e51329fd55b3e36e1059d31bf80fa0633555f5a916af10f227a2",
  "BO02:root_link": "fe10b5884928072b0501df800afe40883aed36ff1722257cdd433e843eaf1689",
  "BO02:acid_scatter": "e615ba31506944a3df975d34b946b30d1f489a9b713e1bdc8c3bed9c2dcef5fd",
  "BO02:venom_spiral": "9642d7588013a9159ad77f239268cbb21cb800776eb85e618f378c2ca2f3b780",
  "BO02:royal_dive": "da865f392f5482ba9621228efc0ad64dd49e56d4ba163af5834e1c5658e3d133",
  "BO02:amber_trap": "f47ded4b42ac748c478f30984eeedd2eb6f4759415a5662880749405075e55a6",
  "BO02:wing_storm": "213ed867cef23105cda87595b3c685c355f08bc7870f5ef5065090f552cc5183",
  "BO02:crown_open": "a33119d3ec4af7f99dc4ed10eb8477fafbcef572b1de99f6e2a9162ca146c4c6",
  "BO03:glide": "c5fa8081ce0be01b54e74cfcda09ec30dd144aa6141b156c73cbe4290e2a2045",
  "BO03:capacitor_burst": "d4504d8afe83accb781f9eb3418ee374eb6bbeb3c06c4325fdf9b9723b5fa59e",
  "BO03:grave_recall": "0b7a331541ddc942f71b35f1e04e31dd3de40d8266d2bcd9205b7a15d1d6fd89",
  "BO03:stitch_cage": "9e56642921f1503468bfdc17b9ed5295da2d1fe9483f670f2daf7b445cf35842",
  "BO03:needle_fan": "02fc1f9ffe65bccb881cf40ffba71861e68fd6d421c44615ddb94f1d776b2265",
  "BO03:grave_burst": "1d337d17c97eea0db5296e43e44abac4f04b9f56619ef44eb0ea409bbae691a8",
  "BO03:funeral_hook": "74386a02396838da76d9370a73fdd2a579e917c11bf009ba84e5ec2c4cf4063c",
  "BO03:seam_lock": "9647a43a55f6995428bb2f841e05f72d44aa08661910926d70b7f5934a576db0",
  "BO03:runway_pair": "7404c70f54d337a1c57ce7e8ad093034e3664355fed708b0f45f3407883819f8",
  "BO03:sweep_land": "e8e87e5f5930bee970fc948444e650d9609dacecf7321634caf46d588f9acef0",
  "BO04:resonance_ring": "33bd322d065b2ad6974f95ceb57bea63747cd0b1aef32463cb92cba8666c9b33",
  "BO04:sound_blade": "5ce379c6ab15bb976ee7922eaf0f787385ece59161964849efc99d804a5979c0",
  "BO04:war_drum_rage": "0b7a331541ddc942f71b35f1e04e31dd3de40d8266d2bcd9205b7a15d1d6fd89",
  "BO04:crag_leap": "3a090bb6b52cfbf817f2da9223db6cd0627109f07d28f99fd5fd97ac824a528b",
  "BO04:axe_fan": "cb26995c5d8630db81d4fc3c00d693e06486ad487dbe47fd8e997a3fcbe87cb7",
  "BO04:fault_lines": "fd15b3b9f236a64deba760085d97d75156cd0df3fca58249c62eca3a9a0d0121",
  "BO04:boulder_volley": "a72f764adfbbc1a28e5e79471ff4e0d4fdbead80ee14c91df484b16f73767d03",
  "BO04:seismic_crown": "2844adedb39aac18af9b9a4b9cd239c6efa123a702a63fa825d649d7da05747c",
  "BO04:replay_path": "acc957c37cd712f4f395dec9b17bb3f598e9b17f2ef66aeef5dce4f2cc79da5b",
  "BO04:alternating_ring": "234abbfb3a10a18acc3446faf9d470c9c1b2a4014461b9ba2b38be63fae3d46c",
  "BO04:heart_crack": "234abbfb3a10a18acc3446faf9d470c9c1b2a4014461b9ba2b38be63fae3d46c"
}
const BOSS_ACTORS := {
  "BO01": [
    [
      19575,
      270,
      180,
      180
    ],
    [
      27405,
      324,
      210,
      210
    ],
    [
      39150,
      405,
      240,
      240
    ],
    [
      54810,
      500,
      270,
      270
    ],
    [
      78300,
      621,
      300,
      300
    ]
  ],
  "BO02": [
    [
      24494,
      262,
      120,
      150
    ],
    [
      34292,
      315,
      150,
      180
    ],
    [
      48989,
      394,
      180,
      210
    ],
    [
      68584,
      486,
      210,
      240
    ],
    [
      97978,
      604,
      240,
      270
    ]
  ],
  "BO03": [
    [
      24775,
      298,
      100,
      120
    ],
    [
      34685,
      357,
      130,
      150
    ],
    [
      49550,
      446,
      160,
      180
    ],
    [
      69371,
      550,
      190,
      210
    ],
    [
      99101,
      684,
      220,
      240
    ]
  ],
  "BO04": [
    [
      34517,
      352,
      220,
      180
    ],
    [
      48324,
      422,
      250,
      210
    ],
    [
      69034,
      527,
      280,
      240
    ],
    [
      96647,
      650,
      310,
      270
    ],
    [
      138067,
      809,
      340,
      300
    ]
  ]
}
const REFERENCE := [
  [
    988,
    3953,
    208,
    478
  ],
  [
    1356,
    5425,
    250,
    575
  ],
  [
    1778,
    7111,
    296,
    681
  ],
  [
    2253,
    9011,
    346,
    795
  ],
  [
    2781,
    11125,
    399,
    918
  ],
  [
    3363,
    13452,
    456,
    1050
  ],
  [
    3998,
    15994,
    517,
    1190
  ],
  [
    4687,
    18749,
    582,
    1339
  ],
  [
    5430,
    21718,
    651,
    1497
  ],
  [
    6225,
    24901,
    723,
    1664
  ],
  [
    7075,
    28298,
    799,
    1839
  ],
  [
    7977,
    31909,
    879,
    2023
  ]
]
