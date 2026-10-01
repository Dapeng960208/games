extends RefCounted
## Translates the live status_text() emitted by the four biome objective modules.
## Keep counters, timers, route selections and reward branches from the source text.

# Longer clauses precede their shared words so replacements remain contextual.
const ACTION_REPLACEMENTS: Dictionary = {
	# Expedition services share the same live objective header as combat rooms.
	"完成整备后前往第一处矿区": "Finish preparations, then enter the first area",
	"M 查看路线": "M · View route",
	"购买补给，或前往下一站": "Buy supplies, or travel to the next stop",
	"领取成长奖励，继续远征": "Collect your growth reward and continue",
	"首领已击败 · 前往撤离井": "Boss defeated · Head to extraction",
	# B01: brakes, cart, key cores, sorting, beacons and furnace gauges.
	"侧箱：18 金币 + 职业防具 · 清理敌群后可回收": "Side crate: 18 coins + class armor · Recover after clearing enemies",
	"制动完成 · 侧箱已回收": "Brakes released · Side crate recovered",
	"释放制动器": "Release brakes",
	"自由选择顺序": "Choose any order",
	"按 1 → 2 → 3": "Follow 1 → 2 → 3",
	"靠近自动推车": "Stay near the cart to push it",
	"取回钥芯": "Recover key cores",
	"不停机：": "Keep machinery running: ",
	"停机：": "Stop machinery: ",
	"搬匣分拣": "Carry and sort crates",
	"搬运中": "Carrying a crate",
	"占据信标": "Hold beacons",
	"切管完成": "Pipe cut complete",
	"精密取芯完成": "Precision core extraction complete",
	"调表 38–62：": "Set gauges to 38–62: ",
	"稳定 ": "Stable ",
	"取芯 ": "Extract core: ",
	# B02: filters, mushrooms, pods, fans, research and reaction tanks.
	"携带中：不能冲刺，E 可放下": "Carrying: dash disabled; E puts it down",
	"搬到东岸净水轮；丢失滤芯可在岸台巢点找回": "Carry to the east-bank water wheel; recover lost filters at bank-platform nest sites",
	"踩住平台待伞盖展开，再按 E 采集": "Stand on a platform until the cap opens, then press E to collect",
	"攻击双环脉纹主囊；斑点假囊受击会鼓泡": "Attack main pods with double-ring veins; spotted decoy pods bubble when hit",
	"顺序自选；旋转风标过载时 E 中断并重试": "Choose any order; press E to interrupt and retry when the rotating vane overloads",
	"第三包：": "Third package: ",
	"，清场后领取": "; collect after clearing enemies",
	"开堰门引流；中央排空杆可降低收益提前完成": "Open sluice gates to divert fluid; the central drain lever completes early with reduced rewards",
	"净化风机": "Purification fans",
	"反应槽": "Reaction tanks",
	"研究包": "Research packages",
	"滤芯": "Filters",
	"灯蕈": "Lamp mushrooms",
	"主囊": "Main pods",
	# B03: docking arms, lamps, magnetic carts, reactors, parts and cargo.
	"校准两条对接臂": "Calibrate both docking arms",
	"E启动后守住三道刻度；损坏只退当前刻度": "Press E to start, then defend three calibration marks; damage resets only the current mark",
	"搬运电池点亮应急灯": "Carry batteries to power emergency lamps",
	"携带电池，前往未亮灯": "Carrying a battery; head to an unlit lamp",
	"E拾取电池，一次携带一块": "E picks up one battery at a time",
	"点灯顺序改变货轨与来敌方向": "Lighting order changes cargo tracks and incoming enemy directions",
	"磁力引导维修车": "Guide repair carts with magnetism",
	"E切换吸/排；": "E switches attraction/repulsion; pulse in ",
	"秒后脉冲，箭头锁定后走绝缘外圈": "s; use the insulated outer ring once the arrow locks",
	"依序冷却反应罐": "Cool reactor tanks in order",
	"阀门导冷雾至": "Valve routes cooling mist to tank ",
	"号罐；过热后E修复重试": "; press E to repair and retry after overheating",
	"原型部件交付": "Deliver prototype parts",
	"携带部件，送往中央装配台": "Carrying a part; deliver it to the central assembly table",
	"从移动传送带拾取部件": "Pick up parts from moving conveyor belts",
	"E旋转薄掩体切换挡弹方向": "E rotates thin cover to change the direction it blocks shots",
	"货舱回收": "Recover cargo pods",
	"控制台选择": "Use the console to select interception point ",
	"号拦截位，或普攻射落；落地预警后E回收": ", or shoot pods down with basic attacks; press E to recover after the landing warning",
	# B04: resonance locks, escort, reflected beams, soundprints, lamps and discs.
	"拆除共鸣锁": "Remove resonance locks",
	"E 开始拆锁，站近保持。顺序改变环波与径向波": "Press E to begin removing a lock and stay nearby; order changes ring and radial waves",
	"护送光点": "Escort the light mote",
	" 段；选择路线后靠近护送。原始攻击可把敌人引向回声": " segments; choose a route and stay near to escort; primary attacks can draw enemies toward echoes",
	"已照亮铭文": "Inscriptions lit",
	"E 转动反射石 45°，保持场景光束对准铭文": "E rotates reflector stones by 45°; keep the scene beam aimed at inscriptions",
	"装入声纹": "Install soundprints",
	"当前携带：无": "Currently carrying: none",
	"当前携带：": "Currently carrying: ",
	"。对照形状，线结可用普攻切断": "; match shapes; basic attacks can cut thread knots",
	"出口光束": "Exit beams",
	"E 搬灯，再在接收器 E 安放。两灯可选金币离开，三灯全保": "Press E to carry a lamp, then E at a receiver to place it; two lamps allow a coins-only exit, three preserve all rewards",
	"踩盘顺序：": "Disc stepping order: ",
	"；错误不清进度，回声落在旧位置": "; mistakes preserve progress; echoes land at the previous position",
	"圆环": "Ring",
	"三道纹": "Triple stripes",
	"①圆": "① Circle",
	"③三角": "③ Triangle",
	"⑤菱": "⑤ Diamond",
	"三角": "Triangle",
	# Shared reward and timer fragments retain the source's numeric values.
	"无装备": "No gear",
	"职业防具": "class armor",
	"机动装备": "mobility gear",
	"生存装备": "survival gear",
	"2 件进攻装备": "2 offensive gear items",
	"进攻装备": "offensive gear",
	"防具": "armor",
	"金币": "coins",
	" 秒": " s",
	"；": "; ",
	"（": " (",
	"）": ")",
}

static func translate_action(value: String, english: bool) -> String:
	if not english:
		return value
	var translated := value
	for source: String in ACTION_REPLACEMENTS:
		translated = translated.replace(source, str(ACTION_REPLACEMENTS[source]))
	return translated

static func action_for_status(status: Dictionary, english: bool) -> String:
	# Modern combat modules author complete native sentences, including their
	# live counters. Legacy fixtures continue using contextual replacements.
	if english and not str(status.get("text_en","")).is_empty(): return str(status.text_en)
	return translate_action(str(status.get("text","")),english)
