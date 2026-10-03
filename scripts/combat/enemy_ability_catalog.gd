extends RefCounted
## Ordinary enemy ability authority. Selected difficulty alone unlocks these
## mechanics. Never changes numeric mechanic_tier or level/stat progression.
## One rotating extra stage per cycle keeps all unlocked abilities available
## without increasing a finite baseline sequence by four simultaneous attacks.

const ENTRIES: Dictionary = {
 "M01": {
  "name": "巡庭夹卫",
  "name_en": "Garden Pincer",
  "behavior_id": "pick_sweep",
  "counter": "横向冲刺绕过夹刃正面；基础近战压力，教会攻击间隙，动能伤害",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "repel",
   "thread",
   "screen",
   "return"
  ]
 },
 "M02": {
  "name": "冲锋蛛卫",
  "name_en": "Sunspider Charger",
  "behavior_id": "locked_charge",
  "counter": "侧移诱撞暴露后背；切割站位，适合与定点射手组合，动能伤害",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "gap_ring",
   "slow_pool",
   "guard",
   "fan"
  ]
 },
 "M03": {
  "name": "远程炮手",
  "name_en": "Solar Gunner",
  "behavior_id": "locked_snipe_relocate",
  "counter": "锁定后离开射线或用掩体；远程牵制，不无限后撤，动能伤害",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "thread",
   "repel",
   "decoy",
   "return"
  ]
 },
 "M04": {
  "name": "蜂群微卫",
  "name_en": "Needle Wasp",
  "behavior_id": "shell_sting_leap",
  "counter": "用范围攻击或移动让其扑空；填补空档与围堵，不承担高伤害，动能伤害",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "slow_pool",
   "fan",
   "screen",
   "gap_ring"
  ]
 },
 "M05": {
  "name": "滚轮猎犬",
  "name_en": "Rolling Hound",
  "behavior_id": "arc_roll_expose",
  "counter": "避开弧线后攻击侧翻面；迫使绕圈路线变化，动能伤害",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "repel",
   "thread",
   "return",
   "guard"
  ]
 },
 "M06": {
  "name": "护翼师",
  "name_en": "Wing Welder",
  "behavior_id": "deploy_weld_cover",
  "counter": "绕侧或打碎护幕，护幕破碎后长时间无法重建；保护射手但不提供全向无敌，火焰/灼烧",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "fan",
   "slow_pool",
   "repel",
   "gap_ring"
  ]
 },
 "M07": {
  "name": "磁叉师",
  "name_en": "Magnetic Hook",
  "behavior_id": "hook_tether",
  "counter": "侧闪、用障碍断链，或攻击卷盘打断蓄力；让安全站位发生变化，动能伤害，不能把角色拖入无底坑",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "slow_pool",
   "screen",
   "fan",
   "return"
  ]
 },
 "M08": {
  "name": "塔盾卫",
  "name_en": "Tower Guard",
  "behavior_id": "rotate_rivet_shield",
  "counter": "绕背、攻击晶扣、在转盾窗口集中攻击；高生命与物理护甲的前排，盾击减速后仍有完整反击窗口",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "repel",
   "thread",
   "fan",
   "gap_ring"
  ]
 },
 "M09": {
  "name": "鸣炉者",
  "name_en": "Hearth Cantor",
  "behavior_id": "consume_corpse_haste",
  "counter": "优先打断摇铃或引其离开残骸；收尾优先级支援，防止无穷召唤与金币循环",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "thread",
   "repel",
   "screen",
   "return"
  ]
 },
 "M10": {
  "name": "镰足刺虫",
  "name_en": "Sickle Stalker",
  "behavior_id": "sidestep_thrust",
  "counter": "保持侧向空间，等横移结束再闪；低生命低双抗的物理刺客，窄刺爆发高，失手后及时反击",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "fan",
   "slow_pool",
   "decoy",
   "gap_ring"
  ]
 },
 "M11": {
  "name": "针吻酸炮",
  "name_en": "Acid Needle",
  "behavior_id": "triple_acid_lob",
  "counter": "接近绕到针吻侧后使其停喷转身，或在落点之间移动；低物理防御的法系炮手，腐蚀液直击结算法术伤害并施加腐蚀",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "thread",
   "repel",
   "screen",
   "return"
  ]
 },
 "M12": {
  "name": "育卵萤母",
  "name_en": "Brood Mother",
  "behavior_id": "budgeted_pod_summon",
  "counter": "打破虫卵能阻止孵化并削弱萤母护甲；召唤支援，不无限刷钱，漂浮不代表能越界离场",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "slow_pool",
   "fan",
   "guard",
   "gap_ring"
  ]
 },
 "M13": {
  "name": "剪钳幼蜓",
  "name_en": "Scissor Nymph",
  "behavior_id": "cross_scissor",
  "counter": "向其背后或两段夹角外移动；侧袭角色，可被卡位但不能瞬移背刺，动能伤害",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "repel",
   "thread",
   "decoy",
   "return"
  ]
 },
 "M14": {
  "name": "黏足幼虫",
  "name_en": "Sticky Larva",
  "behavior_id": "sticky_hop",
  "counter": "在起跳时改变方向，范围清理；少量限制走位，与 M04 的直刺和受击形态不同",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "fan",
   "thread",
   "screen",
   "gap_ring"
  ]
 },
 "M15": {
  "name": "掘地锹甲",
  "name_en": "Burrow Stag",
  "behavior_id": "visible_burrow_strike",
  "counter": "看到裂纹离开，并利用出土硬直反击；驱逐站桩，不能在交互安全区破土，动能伤害",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "slow_pool",
   "fan",
   "guard",
   "return"
  ]
 },
 "M16": {
  "name": "搬运丸甲",
  "name_en": "Parcel Beetle",
  "behavior_id": "steal_quest_object",
  "counter": "拦路或击败掉回完整物品；制造追击抉择，所有携带目标都有地图标记和可达返巢点",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "thread",
   "repel",
   "decoy",
   "gap_ring"
  ]
 },
 "M17": {
  "name": "回春萤卫",
  "name_en": "Glow Mender",
  "behavior_id": "limited_heal_pulse",
  "counter": "在开灯阶段打断，或把敌人引出波圈；治疗支援，禁止互相治疗形成拖时循环",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "fan",
   "thread",
   "screen",
   "gap_ring"
  ]
 },
 "M18": {
  "name": "破墙犀甲",
  "name_en": "Wall Rhinoceros",
  "behavior_id": "bite_breakable_wall",
  "counter": "引它打开侧路后攻击软腹，保持与墙面距离；改变局部路径，动能伤害与有限破墙",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "repel",
   "slow_pool",
   "return",
   "guard"
  ]
 },
 "M19": {
  "name": "提灯哨兵",
  "name_en": "Lantern Sentry",
  "behavior_id": "visible_scan_mark",
  "counter": "走出扫描扇或击败哨兵；目标优先级轻型支援，不能隔墙扫描，无直接高伤害",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "thread",
   "repel",
   "screen",
   "return"
  ]
 },
 "M20": {
  "name": "远程弩手",
  "name_en": "Grave Crossbow",
  "behavior_id": "rail_slide_pierce",
  "counter": "观察滑轮端点与射线利用掩体，近身攻击弩架底座；固定范围炮手，动能伤害",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "slow_pool",
   "fan",
   "decoy",
   "gap_ring"
  ]
 },
 "M21": {
  "name": "蹦跳兵",
  "name_en": "Spring Hopper",
  "behavior_id": "spring_jump_ring",
  "counter": "离开落点，等落地回充时打断；跳跃切后排，电击伤害/感电状态",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "repel",
   "thread",
   "screen",
   "return"
  ]
 },
 "M22": {
  "name": "熔糖炮手",
  "name_en": "Molten Sugar",
  "behavior_id": "limited_molten_stream",
  "counter": "绕到坩锅柄侧，攻击倾倒后的暴露内壁；大面积但有限时的封路，火焰/灼烧",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "thread",
   "repel",
   "guard",
   "gap_ring"
  ]
 },
 "M23": {
  "name": "牵引术士",
  "name_en": "Polarity Caller",
  "behavior_id": "polarity_displacement",
  "counter": "在铜环闭合前离开扇区，利用移来的障碍遮射线；空间支援，不能连续控制玩家或拉进深坑",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "slow_pool",
   "fan",
   "screen",
   "return"
  ]
 },
 "M24": {
  "name": "冰雾泵手",
  "name_en": "Cold Mist Warden",
  "behavior_id": "cold_mist_patrol",
  "counter": "先移出雾边后追击，冰雾按固定时长消散；寒冷伤害/寒冷单层减速，不产生冻结",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "thread",
   "repel",
   "decoy",
   "gap_ring"
  ]
 },
 "M25": {
  "name": "护盾卫士",
  "name_en": "Socket Guard",
  "behavior_id": "socket_shield_recharge",
  "counter": "破盾后阻断回充路径或摧毁插座；有进退节奏的前排，不拥有被动无限回复，护盾/电击",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "repel",
   "thread",
   "fan",
   "return"
  ]
 },
 "M26": {
  "name": "裁缝护卫",
  "name_en": "Stitch Defender",
  "behavior_id": "finite_projectile_screen",
  "counter": "停火诱出防御后换侧进攻，或用有限穿透；针对长时间同方向普攻的节奏敌人，不永久封禁远程职业",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "slow_pool",
   "repel",
   "fan",
   "gap_ring"
  ]
 },
 "M27": {
  "name": "节拍铲兵",
  "name_en": "Two-beat Shovel",
  "behavior_id": "numbered_two_beat_sweep",
  "counter": "躲第一段后不要立刻追入第二段，结束后停顿收铲；两段近战节奏教学，动能伤害",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "thread",
   "fan",
   "guard",
   "return"
  ]
 },
 "M28": {
  "name": "疾行斥候",
  "name_en": "Swift Scout",
  "behavior_id": "last_sound_charge",
  "counter": "通过移动射击把其引向旧位置；低生存的听声物理刺客，冲刺伤害高但轨迹固定，与 M04/M14 的扑跳行为不同",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "slow_pool",
   "repel",
   "decoy",
   "gap_ring"
  ]
 },
 "M29": {
  "name": "幻影刀手",
  "name_en": "Phantom Duelist",
  "behavior_id": "solid_ring_decoy",
  "counter": "认脚底实心环定位真身，有限假影会自行散去；提防侧袭，不复制玩家 UI 或伪装真实奖励，动能伤害",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "fan",
   "thread",
   "screen",
   "return"
  ]
 },
 "M30": {
  "name": "战鼓祭司",
  "name_en": "War Drum Priest",
  "behavior_id": "finite_shield_network",
  "counter": "打断最末一鼓、拉走一个友军、或优先破网；连接型支援，不能与同种互相无限护盾",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "slow_pool",
   "repel",
   "fan",
   "gap_ring"
  ]
 },
 "M31": {
  "name": "冷晶弩手",
  "name_en": "Crystal Crossbow",
  "behavior_id": "single_refraction_beam",
  "counter": "走出整个折线路径或借高掩体；一次折射远程威胁，寒冷伤害，禁止无限反射",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "thread",
   "repel",
   "screen",
   "return"
  ]
 },
 "M32": {
  "name": "跃袭猎手",
  "name_en": "Leaping Hunter",
  "behavior_id": "shadow_arc_leap",
  "counter": "看影移动到弧线内侧，落地露出腰腹可反击；地形相关突袭，动能伤害，不跨不可通行边界",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "fan",
   "slow_pool",
   "guard",
   "gap_ring"
  ]
 },
 "M33": {
  "name": "绳网猎手",
  "name_en": "Rope Netter",
  "behavior_id": "two_breakable_slow_lines",
  "counter": "提前打断、攻击绳结或绕外围；局部路线限制，绳束只减速不持续硬控",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "repel",
   "fan",
   "screen",
   "return"
  ]
 },
 "M34": {
  "name": "反击卫",
  "name_en": "Counter Warden",
  "behavior_id": "bounded_counter_stance",
  "counter": "看姿态停火、绕背或趁换势攻击；需要节奏切换的重型前排，动能伤害，单次触发反击有上限",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "thread",
   "repel",
   "fan",
   "gap_ring"
  ]
 },
 "M35": {
  "name": "窃灯手",
  "name_en": "Lantern Thief",
  "behavior_id": "steal_scene_lamp",
  "counter": "集火发亮腹部追回灯，或把其引离目标点；可逆场景干扰，不隐藏伤害预警、不破坏背包物品",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "slow_pool",
   "fan",
   "guard",
   "return"
  ]
 },
 "M36": {
  "name": "雷符爆破兵",
  "name_en": "Thunder Bomber",
  "behavior_id": "safe_disarm_ring",
  "counter": "先击毁或远离冲击圈；可被主动安全拆除的逼近爆发，不死亡追爆，不产生额外金币链",
  "counter_en": "Read the warning; avoid the locked shape",
  "mechanisms": [
   "thread",
   "repel",
   "screen",
   "fan"
  ]
 },
 "M37": {
  "name": "琥珀织网螳",
  "name_en": "Resin Weaver",
  "behavior_id": "resin_fork_weaver",
  "counter": "击破丝锚，再侧闪牵引",
  "counter_en": "Break thread anchors; sidestep pull",
  "mechanisms": [
   "repel",
   "slow_pool",
   "screen",
   "gap_ring"
  ]
 },
 "M38": {
  "name": "晶翅回针蛾",
  "name_en": "Glasswing Moth",
  "behavior_id": "glasswing_return_sting",
  "counter": "针刺会原路返回，离开整条射线",
  "counter_en": "Leave the lane before the sting returns",
  "mechanisms": [
   "thread",
   "repel",
   "decoy",
   "gap_ring"
  ]
 },
 "M39": {
  "name": "鼓腹震巢虫",
  "name_en": "Hive Drummer",
  "behavior_id": "hive_echo_drummer",
  "counter": "先退离内震，再进入外环安全心",
  "counter_en": "Step out, then enter the safe core",
  "mechanisms": [
   "thread",
   "fan",
   "guard",
   "return"
  ]
 },
 "M40": {
  "name": "提灯引魂僵",
  "name_en": "Lantern Lurer",
  "behavior_id": "lantern_lure_keeper",
  "counter": "侧闪牵引，再穿过亮起的缺口",
  "counter_en": "Dodge pull; use the lit ring gap",
  "mechanisms": [
   "slow_pool",
   "fan",
   "screen",
   "return"
  ]
 },
 "M41": {
  "name": "缝袋抛种僵",
  "name_en": "Seed Bomber",
  "behavior_id": "seed_satchel_bomber",
  "counter": "两侧种池留出中间通道",
  "counter_en": "Use the lane between seed pools",
  "mechanisms": [
   "thread",
   "repel",
   "guard",
   "gap_ring"
  ]
 },
 "M42": {
  "name": "棺盖铁卫",
  "name_en": "Coffin Bulwark",
  "behavior_id": "coffin_lid_bulwark",
  "counter": "耗尽两次盾幕可打断推盾，或绕后",
  "counter_en": "Spend two screen charges or flank",
  "mechanisms": [
   "slow_pool",
   "fan",
   "thread",
   "return"
  ]
 },
 "M43": {
  "name": "钟铃送葬僵",
  "name_en": "Funeral Bell",
  "behavior_id": "funeral_bell_caller",
  "counter": "普攻击断铃声，避开迟缓扇面",
  "counter_en": "Interrupt bell; avoid slowing cone",
  "mechanisms": [
   "thread",
   "repel",
   "screen",
   "gap_ring"
  ]
 },
 "M44": {
  "name": "稻草换影僵",
  "name_en": "Straw Effigy",
  "behavior_id": "straw_effigy_switcher",
  "counter": "实线脚环是真身；躲开弧形落点",
  "counter_en": "Solid foot ring marks owner; dodge leap",
  "mechanisms": [
   "slow_pool",
   "fan",
   "screen",
   "return"
  ]
 },
 "M45": {
  "name": "南瓜缝线医",
  "name_en": "Stitch Mender",
  "behavior_id": "pumpkin_stitch_mender",
  "counter": "普攻击断缝合；治疗后会后撤",
  "counter_en": "Interrupt stitches before the retreat",
  "mechanisms": [
   "thread",
   "repel",
   "screen",
   "gap_ring"
  ]
 },
 "M46": {
  "name": "双斧回旋兽人",
  "name_en": "Twin Axe Raider",
  "behavior_id": "twin_axe_returner",
  "counter": "两条斧线会返回，横移出整条轨迹",
  "counter_en": "Leave both outgoing and return lanes",
  "mechanisms": [
   "slow_pool",
   "repel",
   "guard",
   "gap_ring"
  ]
 },
 "M47": {
  "name": "岩索拖拽兽人",
  "name_en": "Rock Chain Raider",
  "behavior_id": "rock_chain_dragger",
  "counter": "钩索落空就不会接劈砍",
  "counter_en": "Dodge hook to cancel the cleave",
  "mechanisms": [
   "thread",
   "fan",
   "screen",
   "return"
  ]
 },
 "M48": {
  "name": "战鼓催阵兽人",
  "name_en": "War Drum Marshal",
  "behavior_id": "war_drum_marshal",
  "counter": "打断鼓声，再退离脚边震波",
  "counter_en": "Interrupt drum; leave the shockwave",
  "mechanisms": [
   "thread",
   "repel",
   "screen",
   "return"
  ]
 },
 "M49": {
  "name": "獠牙冲阵兽人",
  "name_en": "Tusk Charger",
  "behavior_id": "tusk_lane_breaker",
  "counter": "诱撞墙；未撞墙会反身后扫",
  "counter_en": "Bait a wall; avoid the rear cleave",
  "mechanisms": [
   "slow_pool",
   "fan",
   "guard",
   "gap_ring"
  ]
 },
 "M50": {
  "name": "投网猎手兽人",
  "name_en": "Net Hunter",
  "behavior_id": "net_snare_hunter",
  "counter": "击破网锚可取消接续射击",
  "counter_en": "Break net anchor to cancel the shot",
  "mechanisms": [
   "repel",
   "slow_pool",
   "screen",
   "gap_ring"
  ]
 },
 "M51": {
  "name": "巨盾反击食人魔",
  "name_en": "Slab Counter Ogre",
  "behavior_id": "slab_counter_ogre",
  "counter": "停手或绕后，不触发反击推击",
  "counter_en": "Stop hitting or flank to deny the counter",
  "mechanisms": [
   "thread",
   "fan",
   "guard",
   "return"
  ]
 },
 "M52": {
  "name": "裂地锤手食人魔",
  "name_en": "Fault Hammer Ogre",
  "behavior_id": "fault_hammer_ogre",
  "counter": "先后两条垂直裂缝，换到安全象限",
  "counter_en": "Move into a safe quadrant between fissures",
  "mechanisms": [
   "slow_pool",
   "fan",
   "screen",
   "return"
  ]
 },
 "M53": {
  "name": "掷桶火油食人魔",
  "name_en": "Oil Cask Ogre",
  "behavior_id": "oil_cask_ogre",
  "counter": "先离开油池，再绕开点火扇面",
  "counter_en": "Leave oil, then flank the flame cone",
  "mechanisms": [
   "thread",
   "repel",
   "guard",
   "gap_ring"
  ]
 },
 "M54": {
  "name": "震步搬岩食人魔",
  "name_en": "Boulder Step Ogre",
  "behavior_id": "boulder_step_ogre",
  "counter": "进入震环内心，再侧移躲飞石",
  "counter_en": "Enter ring core, then sidestep boulder",
  "mechanisms": [
   "slow_pool",
   "repel",
   "screen",
   "return"
  ]
 }
}

const MECHANISMS: Dictionary = {
 "repel": {"name":"驱退震掌","name_en":"Repelling Palm","counter":"侧闪扇面；背后安全","counter_en":"Sidestep cone; rear is safe","kind":"pull","shape":"cone","angle":1.4,"range":105.0,"repel":true,"pull_distance":42.0,"damage_multiplier":0.45},
 "thread": {"name":"锚定绊索","name_en":"Anchored Snare","counter":"击破末端锚点，或绕开细线","counter_en":"Break endpoint or avoid the line","kind":"ground_area","shape":"line","radius":10.0,"range":205.0,"duration":2.6,"breakable":true,"anchor_health":16.0,"damage_multiplier":0.0,"status":{"id":"slow","duration":0.65,"magnitude":0.78}},
 "screen": {"name":"双次护幕","name_en":"Two-charge Screen","counter":"绕后；盾幕只拦两发","counter_en":"Flank; screen blocks two shots","kind":"guard","mode":"screen","duration":2.2,"charges":2,"angle":1.6,"radius":38.0,"damage_multiplier":0.0},
 "return": {"name":"折返飞刃","name_en":"Returning Blade","counter":"离开锁定射线，提防折返","counter_en":"Leave frozen lane; blade returns","kind":"projectile","shape":"line","count":1,"range":235.0,"radius":7.0,"speed":240.0,"returning":true,"pierce":true,"damage_multiplier":0.5},
 "gap_ring": {"name":"缺口震环","name_en":"Open-sector Ring","counter":"进内圈或从侧面缺口撤离","counter_en":"Enter core or use side gap","kind":"ground_area","shape":"ring","center":"self","radius":125.0,"inner_radius":48.0,"ring_gap_degrees":80.0,"aim_offset":90.0,"duration":0.0,"damage_multiplier":0.65},
 "slow_pool": {"name":"迟滞残迹","name_en":"Slowing Residue","counter":"锁定后离开落点","counter_en":"Leave the marked landing after lock","kind":"ground_area","shape":"circle","radius":39.0,"range":220.0,"duration":2.2,"damage_multiplier":0.0,"status":{"id":"slow","duration":0.65,"magnitude":0.78}},
 "guard": {"name":"转向护甲","name_en":"Facing Ward","counter":"打断施法，或绕到未护住的背后","counter_en":"Interrupt or flank the unguarded rear","kind":"guard","mode":"directional","angle":1.6,"radius":35.0,"range":95.0,"duration":2.7,"charges":2,"max_targets":1,"shield_ratio":0.12,"exclude_self":false,"interruptible":true,"damage_multiplier":0.0},
 "fan": {"name":"分路针芒","name_en":"Split Needles","counter":"沿两条射线之间穿过","counter_en":"Use the gap between both lanes","kind":"projectile","shape":"line","count":2,"projectile_angles":[-19.0,19.0],"range":230.0,"radius":5.0,"speed":270.0,"damage_multiplier":0.45},
 "decoy": {"name":"留影诱招","name_en":"Marked Afterimage","counter":"实线脚环标出真身","counter_en":"Solid foot ring identifies the owner","kind":"decoy","count":1,"radius":60.0,"duration":2.2,"solid_owner_ring":true,"damage_multiplier":0.0}
}

static func entry(enemy_id: String) -> Dictionary:
 return ENTRIES.get(enemy_id, {}).duplicate(true)

static func unlocks(enemy_id: String, difficulty: int) -> Array[Dictionary]:
 var result: Array[Dictionary] = []
 var record: Dictionary = ENTRIES.get(enemy_id, {})
 var list: Array = record.get("mechanisms", [])
 for index: int in range(mini(clampi(difficulty, 0, 4), list.size())):
  var key: String = str(list[index])
  var info: Dictionary = MECHANISMS[key].duplicate(true)
  info["unlock_difficulty"] = index + 1
  info["mechanism_id"] = key
  info["ability_id"] = enemy_id + ":d" + str(index + 1) + ":" + key
  info["name"] = str(record.name) + "·" + str(info.name)
  info["name_en"] = str(record.name_en) + " · " + str(info.name_en)
  result.append(info)
 return result

static func apply(source: Dictionary, difficulty: int) -> Dictionary:
 var result: Dictionary = source.duplicate(true)
 var id: String = str(result.get("enemy_id", ""))
 if not ENTRIES.has(id) or str(result.get("rank", "normal")) == "boss": return result
 result["difficulty_mechanics"] = {"difficulty":clampi(difficulty,0,4),"unlocked":unlocks(id,difficulty),"max_extra_stages":1}
 return result

static func extra_command(enemy_id: String, difficulty: int, cycle: int) -> Dictionary:
 var available: Array[Dictionary] = unlocks(enemy_id, difficulty)
 if available.is_empty(): return {}
 return available[posmod(cycle + available.size() - 1, available.size())].duplicate(true)

static func decorate(command: Dictionary, profile: Dictionary, index: int) -> Dictionary:
 var result: Dictionary = command.duplicate(true)
 # Summon commands carry the child's enemy_id. Identity always comes from
 # the casting profile, not the requested summoned monster.
 var id: String = str(profile.get("enemy_id", ""))
 var record: Dictionary = ENTRIES.get(id, {})
 if record.is_empty(): return result
 var kind: String = str(result.get("kind", "melee"))
 var words: Dictionary = {"melee":["挥击","Strike"],"pull":["牵引" if not bool(result.get("repel",false)) else "推击","Pull" if not bool(result.get("repel",false)) else "Shove"],"projectile":["折返射击" if bool(result.get("returning",false)) else "射击","Return shot" if bool(result.get("returning",false)) else "Shot"],"charge":["撤步" if bool(result.get("retreat",false)) else "突进","Retreat" if bool(result.get("retreat",false)) else "Rush"],"ground_area":["震环" if str(result.get("shape","")) == "ring" else "布阵","Ring" if str(result.get("shape","")) == "ring" else "Field"],"guard":["护幕","Guard"],"haste":["催阵","Haste"],"heal":["疗愈","Mend"],"counter":["反击架势","Counter"],"summon":["育卵","Brood"],"decoy":["换影","Decoy"],"utility":["战术","Tactic"]}
 var label: Array = words.get(kind,["技能","Skill"])
 result["ability_id"] = result.get("ability_id",id+":base:"+str(index)+":"+kind)
 result["ability_name"] = result.get("name",str(record.name)+"·"+str(label[0]))
 result["ability_name_en"] = result.get("name_en",str(record.name_en)+" · "+str(label[1]))
 result["counter_cue"] = result.get("counter",record.counter)
 result["counter_cue_en"] = result.get("counter_en",record.counter_en)
 result["caster_enemy_id"] = id
 result["icon_id"] = id
 result["vfx_identity"] = id+":"+str(result.get("mechanism_id",profile.get("behavior_id","")))
 result["fx_color"] = {"B01":Color("60bcb0"),"B02":Color("bd9a39"),"B03":Color("be856b"),"B04":Color("ae816c")}.get(str(profile.get("biome_id","")),Color("d49762"))
 result["essential_danger"] = true
 result["max_active_hazards"] = mini(2,int(result.get("max_active_hazards",2)))
 result["max_targets"] = mini(3,int(result.get("max_targets",2)))
 return result

static func command_info(command: Dictionary, english: bool = false) -> Dictionary:
 return {"id":str(command.get("ability_id","")),"name":str(command.get("ability_name_en" if english else "ability_name","")),"counter":str(command.get("counter_cue_en" if english else "counter_cue","")),"icon_id":str(command.get("icon_id","")),"stage":int(command.get("stage",0))+1,"stage_count":int(command.get("stage_count",1)),"unlock_difficulty":int(command.get("unlock_difficulty",0))}

static func all_skills(enemy_id: String, difficulty: int, resolved_profile: Dictionary = {}) -> Array[Dictionary]:
 if enemy_id.begins_with("B06-M"): return preload("res://scripts/combat/b06_ability_catalog.gd").all_skills(enemy_id,difficulty,resolved_profile)
 if enemy_id.begins_with("B05-M"): return preload("res://scripts/combat/b05_enemy_skills.gd").all_skills(enemy_id,difficulty,resolved_profile)
 var source: Dictionary = resolved_profile.duplicate(true)
 if source.is_empty():
  var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
  if raw is Dictionary: source = raw.get("enemies",{}).get(enemy_id,{}).duplicate(true)
 if source.is_empty() or not ENTRIES.has(enemy_id): return []
 source["difficulty"] = clampi(difficulty,0,4)
 source = apply(source,difficulty)
 # Runtime load avoids a static catalog/brain dependency cycle. The same
 # sequence builder supplies codex/document rows, never a parallel move list.
 var script: Script = load("res://scripts/combat/enemy_brain.gd")
 var brain: RefCounted = script.new()
 brain.configure(source)
 var commands: Array[Dictionary] = brain._build_sequence(false)
 var result: Array[Dictionary] = []
 for index: int in commands.size():
  result.append(_skill_record(commands[index],source,0,false,brain.timing_for_command(commands[index],index)))
 # Finite support actors change tactics after their two healing charges.
 if enemy_id in ["M17","M45"]:
  brain.set("_heal_pulses",2)
  for command: Dictionary in brain._build_sequence(false):
   if str(command.kind) in ["melee","projectile"]:
    command["ability_id"] = enemy_id+":spent:"+str(command.kind)
    command["counter_cue"] = "两次治疗用尽后改用此招"
    command["counter_cue_en"] = "Used after both healing charges are spent"
    result.append(_skill_record(command,source,0,false,brain.timing_for_command(command,0)))
 for extra: Dictionary in unlocks(enemy_id,4):
  var command: Dictionary = brain._skill(str(extra.kind),extra)
  command = decorate(command,source,result.size())
  result.append(_skill_record(command,source,int(extra.unlock_difficulty),int(extra.unlock_difficulty)>clampi(difficulty,0,4),brain.timing_for_command(command,commands.size())))
 for skill: Dictionary in result:
  skill["replaced"] = enemy_id == "M36" and int(skill.min_difficulty)>0 and int(skill.min_difficulty)<clampi(difficulty,0,4)
  skill["selected"] = not bool(skill.locked) and not bool(skill.replaced)
 return result

static func _skill_record(command: Dictionary, profile: Dictionary, minimum: int, locked: bool, timing: Dictionary) -> Dictionary:
 var tell: float = float(timing.tell_seconds)
 var lock: float = float(timing.lock_seconds)
 var cooldown: float = float(timing.cooldown)
 var trigger: String = "基准连段，按真实顺序施放"
 var trigger_en: String = "Base sequence, cast in shown order"
 if minimum > 0:
  trigger = "难度%d解锁；每轮末尾轮换一招，额外招式至多1段" % minimum
  trigger_en = "Unlocks at D%d; one rotating extra stage per cycle" % minimum
 if str(profile.get("enemy_id","")) == "M36" and minimum > 0:
  trigger = "一次性爆破兵：仅选当前最高难度招式作前奏，再单次放电；较低档招式被替代"
  trigger_en = "One-use bomber: newest unlocked prelude replaces lower tiers, then one discharge"
 if bool(command.get("requires_counter_hit",false)):
  trigger = "仅在反击架势被命中后接续"
  trigger_en = "Only after the counter stance is hit"
 if bool(command.get("requires_pull_hit",false)):
  trigger = "仅在前段钩索命中后接续"
  trigger_en = "Only after the hook connects"
 return {"ability_id":command.get("ability_id",""),"icon_id":command.get("icon_id",""),"locked":locked,"unlocked":not locked,"min_difficulty":minimum,"name":command.get("ability_name",""),"name_en":command.get("ability_name_en",""),"effect":_effect_text(command,false,profile),"effect_en":_effect_text(command,true,profile),"trigger":trigger,"trigger_en":trigger_en,"counter":command.get("counter_cue",""),"counter_en":command.get("counter_cue_en",""),"command":command.duplicate(true),"cooldown":cooldown,"tell_seconds":tell,"lock_seconds":lock,"warning_timing":timing.duplicate(true)}

static func _effect_text(command: Dictionary, english: bool, profile: Dictionary = {}) -> String:
 command = effective_command(command,profile)
 if command.is_empty(): return "Invalid combat profile" if english else "战斗资料无效"
 var kind: String = str(command.kind)
 var pieces: Array[String] = []
 var labels: Dictionary = {"melee":["近战","Melee"],"projectile":["弹体","Projectile"],"charge":["位移","Motion"],"ground_area":["地面效果","Ground effect"],"pull":["推拉","Displacement"],"guard":["护盾","Guard"],"haste":["加速","Haste"],"heal":["治疗","Heal"],"counter":["反击","Counter"],"decoy":["诱饵","Decoy"],"summon":["召唤","Summon"],"utility":["交互","Utility"]}
 pieces.append(str(labels.get(kind,[kind,kind])[1 if english else 0]))
 var units: Array = [["range","射程","range"],["radius","半径","radius"],["inner_radius","安全内半径","safe inner radius"],["duration","持续秒","duration s"],["count","数量","count"],["charges","次数","charges"],["max_targets","目标上限","max targets"],["pull_distance","推拉距离","displacement"],["heal_ratio","治疗比率","heal ratio"],["shield_ratio","护盾比率","shield ratio"],["multiplier","移速倍率","speed ratio"],["speed","速度","speed"],["travel_distance","位移长度","travel distance"],["tick_interval","生效间隔秒","tick interval s"],["max_active_hazards","地面残留上限","hazard cap"],["anchor_health","锚点耐久","anchor HP"],["cover_hp","掩体耐久","cover HP"],["pod_health","卵舱耐久","pod HP"],["max_alive","召唤存活上限","summon cap"],["hit_cap","承击上限","hit cap"],["max_receives","每目标治疗上限","heal receipt cap"],["hatch_delay","孵化秒","hatch s"],["ring_gap_degrees","安全缺口角度","safe gap degrees"]]
 for unit: Array in units:
  if str(unit[0]) == "max_active_hazards" and kind != "ground_area": continue
  if str(unit[0]) == "max_targets" and kind not in ["guard","heal","haste"]: continue
  if command.has(unit[0]) and float(command[unit[0]]) > 0.0: pieces.append(str(unit[2 if english else 1])+" "+str(command[unit[0]]))
 pieces.append(("coefficient " if english else "伤害系数 ")+str(command.get("damage_multiplier",1.0)))
 if bool(command.get("returning",false)): pieces.append("returns on frozen lane; one hit per cast" if english else "沿锁定轨迹折返；单次施法仅命中一次")
 if bool(command.get("break_interrupts_owner",false)): pieces.append("breaking anchor cancels follow-up" if english else "破锚取消后续招式")
 if bool(command.get("break_exposes_owner",false)): pieces.append("depleting screen exposes caster" if english else "耗尽护幕使施法者露出破绽")
 if bool(command.get("retreat",false)): pieces.append("moves away from locked aim" if english else "沿锁定方向后撤")
 var status: Dictionary = command.get("status",{})
 if not status.is_empty():
  var state_text: String = str(status.get("id",""))+" "+str(status.get("duration",0))+"s"
  if str(status.get("id","")) == "slow": state_text += (" speed ×" if english else " 移速×")+str(status.get("magnitude",0.8))
  if status.has("power"): state_text += (" base power " if english else " 基础强度 ")+str(status.power)
  pieces.append(state_text)
 if command.has("mode"): pieces.append(("mode " if english else "模式 ")+str(command.mode))
 if command.has("action"): pieces.append(("action " if english else "交互 ")+str(command.action))
 if bool(command.get("consume_corpse",false)): pieces.append("consumes a corpse" if english else "需消耗尸体")
 if bool(command.get("break_on_range",false)): pieces.append("breaks out of range" if english else "离开范围断开")
 if bool(command.get("interruptible",false)): pieces.append("direct hits interrupt" if english else "普攻击断")
 if bool(command.get("front_hits_only",false)): pieces.append("front direct hits trigger counter; flanking hits do not" if english else "仅正面直接攻击触发反击；背击不触发")
 return " · ".join(pieces)

static func effective_command(source: Dictionary, profile: Dictionary) -> Dictionary:
 # Runtime-loaded numerical producer avoids a static Catalog↔Numbers cycle.
 # Endpoint durability carries tier/D/calibration scaling, not merely ×10.
 var result: Dictionary = source.duplicate(true)
 if int(profile.get("ruleset_version",1)) == 2:
  var numbers: Script = load("res://scripts/combat/enemy_numerical_v2.gd")
  result = numbers.command(source,profile)
  if result.is_empty(): return {}
 var kind: String = str(result.get("kind",""))
 if kind == "ground_area" and float(result.get("duration",0)) > 0.0: result["tick_interval"] = clampf(float(result.get("tick_interval",0.65)),0.35,2.0)
 if kind == "projectile": result["speed"] = clampf(float(result.get("speed",420)),40,2400)
 # Runtime's breakable line/cover endpoints clamp legacy values here. Pods
 # go directly to their own constructor and retain the numerical packet HP.
 var scale: float = 10.0 if int(profile.get("ruleset_version",1))==2 else 1.0
 for key: String in ["anchor_health","cover_hp"]:
  if result.has(key): result[key] = clampf(float(result[key]),scale,80.0*scale)
 return result
