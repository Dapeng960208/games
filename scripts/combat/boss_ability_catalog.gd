extends RefCounted
## Four additional faction abilities, unlocked cumulatively by difficulty.
## Geometry is rebuilt only during tracking, then frozen by BossBrain.
const UNLOCKS := {
	"BO01":["prism_fan","solar_mines","gear_dash","eclipse_ring"],
	"BO02":["venom_spiral","royal_dive","amber_trap","wing_storm"],
	"BO03":["needle_fan","grave_burst","funeral_hook","seam_lock"],
	"BO04":["axe_fan","fault_lines","boulder_volley","seismic_crown"],
}
const NAMES := {
	"prism_fan":["棱晶连射","Prismatic volley"],"solar_mines":["日耀落雷","Solar thunderfall"],"gear_dash":["齿轮突进","Gear rush"],"eclipse_ring":["日蚀光环","Eclipse halo"],
	"venom_spiral":["回旋毒针","Spiraling venom"],"royal_dive":["虫后俯冲","Royal dive"],"amber_trap":["琥珀毒巢","Amber traps"],"wing_storm":["振翼风暴","Wing storm"],
	"needle_fan":["缝针散射","Needle spread"],"grave_burst":["墓火三连","Gravefire triad"],"funeral_hook":["送葬钩索","Funeral hook"],"seam_lock":["缝线封锁","Seam barricade"],
	"axe_fan":["裂甲斧扫","Rending axe"],"fault_lines":["双脊断层","Twin fault lines"],"boulder_volley":["飞岩齐射","Boulder volley"],"seismic_crown":["震地王冠","Seismic crown"],
	"hammer_fan":["机关臂横扫","Clockwork sweep"],"ladle_drag":["闪电拖痕","Lightning trace"],"solar_cross":["日耀十字","Solar cross"],"slag_lane":["日耀雷道","Solar lane"],"back_heat":["炉心过载","Core overload"],
	"root_fork":["蚁酸分叉","Acid fork"],"spore_pod":["蚁酸弹池","Acid pool"],"acid_scatter":["蚁酸散射","Acid scatter"],"root_link":["虫翼切风","Wing slash"],"brood_eggs":["召唤虫卵","Brood eggs"],"crown_open":["虫后开甲","Open carapace"],
	"glide":["缝线牵引","Stitch pull"],"capacitor_burst":["糖桶投掷","Candy barrel"],"stitch_cage":["缝线牢笼","Stitch cage"],"grave_recall":["墓穴召回","Grave recall"],"runway_pair":["双缝针道","Stitch lanes"],"sweep_land":["镇长扑击","Mayor slam"],
	"resonance_ring":["震地重击","Ground slam"],"sound_blade":["酋长冲锋","Warchief charge"],"crag_leap":["崩岩跳斩","Crag leap"],"war_drum_rage":["战鼓狂怒","War drum rage"],"replay_path":["岩缝追击","Rock fissures"],"alternating_ring":["外圈震击","Outer slam"],"heart_crack":["裂地喘息","Exhausted slam"],
}
const COLORS := {"BO01":Color("56cddb"),"BO02":Color("afcf63"),"BO03":Color("b790db"),"BO04":Color("e6ac6b")}

static func unlocked(boss_id: String, difficulty: int) -> Array:
	return UNLOCKS.get(boss_id,[]).slice(0,clampi(difficulty,0,4))

static func tier(boss_id: String, action: String) -> int:
	return UNLOCKS.get(boss_id,[]).find(action)+1

static func title(action: String, english: bool = false) -> String:
	return str(NAMES.get(action,[action,action])[1 if english else 0])

static func build(boss_id: String, action: String, origin: Vector2, target: Vector2) -> Dictionary:
	if not action in UNLOCKS.get(boss_id,[]): return {}
	var direction := origin.direction_to(target)
	if direction.is_zero_approx(): direction = Vector2.RIGHT
	var side := direction.orthogonal()
	var base := {"action_id":action,"thematic_action":action,"behavior_id":"boss_"+boss_id.to_lower(),"boss_id":boss_id,"unlock_difficulty":tier(boss_id,action),"origin":origin,"target":target,"direction":direction,"tracks_target":true,"tell":1.2,"lock":.5,"recovery":1.7,"cooldown":7.0,"damage_multiplier":1.0,"fx_color":COLORS[boss_id]}
	match action:
		"prism_fan":
			base.merge({"kind":"projectile","shape":"line","paths":_fan(origin,direction,5,.24,700),"count":5,"width":18.0,"speed":390.0,"projectile_radius":8.0,"damage_multiplier":.42,"damage_type":"magic","status":{"id":"shock","duration":2.0}}, true)
		"solar_mines":
			base.merge({"kind":"ground_area","shape":"circle","targets":[target-side*150,target,target+side*150],"radius":70.0,"duration":0.0,"damage_multiplier":1.15,"damage_type":"magic","tell":1.4,"cooldown":8.5}, true)
		"gear_dash":
			base.merge({"kind":"charge","shape":"line","range":480.0,"travel_distance":480.0,"width":90.0,"radius":45.0,"speed":390.0,"damage_multiplier":1.2,"cooldown":9.0}, true)
		"eclipse_ring":
			base.merge({"kind":"ground_area","shape":"ring","target":origin,"radius":410.0,"inner_radius":155.0,"ring_gap_degrees":100.0,"direction":side,"duration":0.0,"damage_multiplier":1.4,"damage_type":"magic","weakpoint_id":"eclipse_core","weakpoint_duration":2.0,"tell":1.5,"recovery":2.0,"cooldown":10.0}, true)
		"venom_spiral":
			var paths: Array = []
			for index: int in 4:
				var angle := -.6+index*.4
				paths.append([origin,origin+direction.rotated(angle)*220,target+side*(index-1.5)*65])
			base.merge({"kind":"projectile","shape":"line","paths":paths,"count":4,"width":18.0,"speed":310.0,"projectile_radius":8.0,"damage_multiplier":.42,"status":{"id":"corrosion","duration":2.4}}, true)
		"royal_dive":
			base.merge({"kind":"charge","shape":"line","path_mode":"leap","range":480.0,"travel_distance":480.0,"width":28.0,"radius":96.0,"speed":450.0,"landing_only":true,"landing_shape":"circle","damage_along_path":false,"damage_multiplier":1.12,"status":{"id":"corrosion","duration":2.0},"cooldown":8.0}, true)
		"amber_trap":
			base.merge({"kind":"ground_area","shape":"circle","targets":[target-direction*125+side*115,target+direction*125+side*115,target-side*115],"radius":66.0,"duration":3.0,"tick_interval":.9,"max_active_hazards":2,"lob":true,"damage_multiplier":.3,"status":{"id":"slow","duration":.8,"magnitude":.7},"cooldown":9.0}, true)
		"wing_storm":
			base.merge({"kind":"melee","shape":"cone","range":440.0,"angle":2.3,"damage_multiplier":1.35,"status":{"id":"slow","duration":1.3,"magnitude":.65},"tell":1.45,"cooldown":10.0}, true)
		"needle_fan":
			base.merge({"kind":"projectile","shape":"line","paths":_fan(origin,direction,4,.28,650),"count":4,"width":16.0,"speed":460.0,"projectile_radius":7.0,"damage_multiplier":.4,"status":{"id":"bleed","duration":2.5}}, true)
		"grave_burst":
			base.merge({"kind":"ground_area","shape":"circle","targets":[target-direction*135,target,target+direction*135],"radius":76.0,"duration":0.0,"damage_multiplier":1.0,"status":{"id":"burn","duration":2.0},"tell":1.35}, true)
		"funeral_hook":
			base.merge({"kind":"pull","shape":"line","range":700.0,"width":80.0,"pull_distance":140.0,"damage_multiplier":.85,"status":{"id":"grievous","duration":3.0},"tell":1.4,"cooldown":9.0}, true)
		"seam_lock":
			var a := target-direction*100-side*180
			var b := target+direction*100-side*180
			var c := target+direction*100+side*180
			var d := target-direction*100+side*180
			base.merge({"kind":"ground_area","shape":"line","paths":[[a,b],[b,c],[c,d]],"width":42.0,"duration":0.0,"damage_multiplier":1.2,"status":{"id":"slow","duration":1.5,"magnitude":.7},"tell":1.5,"cooldown":10.0}, true)
		"axe_fan":
			base.merge({"kind":"melee","shape":"cone","range":285.0,"angle":2.15,"damage_multiplier":1.15,"status":{"id":"bleed","duration":2.0}}, true)
		"fault_lines":
			# One fault follows the warned aim. Symmetric side lines left a
			# permanent safe corridor precisely under a stationary target.
			base.merge({"kind":"ground_area","shape":"line","paths":[[origin,origin+direction*720],[origin+side*190,origin+side*190+direction*720]],"width":64.0,"duration":0.0,"damage_multiplier":1.2,"tell":1.4,"cooldown":8.0}, true)
		"boulder_volley":
			base.merge({"kind":"projectile","shape":"line","paths":_fan(origin,direction,3,.35,760),"count":3,"width":28.0,"speed":330.0,"projectile_radius":14.0,"damage_multiplier":.78,"status":{"id":"slow","duration":.9,"magnitude":.8},"cooldown":9.0}, true)
		"seismic_crown":
			base.merge({"kind":"ground_area","shape":"ring","target":origin,"radius":550.0,"inner_radius":250.0,"ring_gap_degrees":105.0,"direction":side,"duration":0.0,"damage_multiplier":1.5,"weakpoint_id":"seismic_exhaustion","weakpoint_duration":2.3,"tell":1.6,"recovery":2.3,"cooldown":11.0}, true)
	return base

static func _fan(origin: Vector2, direction: Vector2, count: int, spread: float, reach: float) -> Array:
	var paths: Array = []
	for index: int in count: paths.append([origin,origin+direction.rotated((index-(count-1)*.5)*spread)*reach])
	return paths
