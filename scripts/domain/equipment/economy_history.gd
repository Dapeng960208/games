extends RefCounted
## Frozen transaction rules: append a new version when prices/costs/membership change.
## Never regenerate v1 from the live catalog: unversioned historical receipts use it.

const CURRENT_VERSION := 1
const V1_UPGRADE_COSTS := [60, 100, 160, 240, 340]
const V1_PRICES := {
	"EQ01": 60, "EQ02": 100, "EQ03": 180, "EQ04": 180, "EQ05": 180, "EQ06": 180,
	"EQ07": 180, "EQ08": 180, "EQ09": 180, "EQ10": 180, "EQ11": 60, "EQ12": 100,
	"EQ13": 140, "EQ14": 140, "EQ15": 140, "EQ16": 140, "EQ17": 140, "EQ18": 140,
	"EQ19": 140, "EQ20": 140, "EQ21": 60, "EQ22": 100, "EQ23": 180, "EQ24": 180,
	"EQ25": 180, "EQ26": 180, "EQ27": 180, "EQ28": 180, "EQ29": 180, "EQ30": 180,
	"EQ31": 60, "EQ32": 100, "EQ33": 120, "EQ34": 120, "EQ35": 120, "EQ36": 120,
	"EQ37": 120, "EQ38": 120, "EQ39": 120, "EQ40": 120, "EQ41": 60, "EQ42": 100,
	"EQ43": 120, "EQ44": 120, "EQ45": 120, "EQ46": 120, "EQ47": 120, "EQ48": 120,
	"EQ49": 120, "EQ50": 120, "EQ51": 60, "EQ52": 100, "EQ53": 160, "EQ54": 160,
	"EQ55": 160, "EQ56": 160, "EQ57": 160, "EQ58": 160, "EQ59": 160, "EQ60": 160,
	"EQ61": 180, "EQ62": 140, "EQ63": 180, "EQ64": 120, "EQ65": 120, "EQ66": 160,
	"EQ67": 180, "EQ68": 140, "EQ69": 180, "EQ70": 120, "EQ71": 120, "EQ72": 160,
	"EQ73": 180, "EQ74": 140, "EQ75": 180, "EQ76": 120, "EQ77": 120, "EQ78": 160,
	"EQ79": 180, "EQ80": 140, "EQ81": 180, "EQ82": 120, "EQ83": 120, "EQ84": 160,
	"EQ85": 180, "EQ86": 140, "EQ87": 180, "EQ88": 120, "EQ89": 120, "EQ90": 160,
	"EQ91": 180, "EQ92": 140, "EQ93": 180, "EQ94": 120, "EQ95": 120, "EQ96": 160,
}
const V1_SETS := {
	"S01": ["EQ03", "EQ13", "EQ23", "EQ33", "EQ43", "EQ53"],
	"S02": ["EQ04", "EQ14", "EQ24", "EQ34", "EQ44", "EQ54"],
	"S03": ["EQ05", "EQ15", "EQ25", "EQ35", "EQ45", "EQ55"],
	"S04": ["EQ06", "EQ16", "EQ26", "EQ36", "EQ46", "EQ56"],
	"S05": ["EQ07", "EQ17", "EQ27", "EQ37", "EQ47", "EQ57"],
	"S06": ["EQ08", "EQ18", "EQ28", "EQ38", "EQ48", "EQ58"],
	"S07": ["EQ09", "EQ19", "EQ29", "EQ39", "EQ49", "EQ59"],
	"S08": ["EQ10", "EQ20", "EQ30", "EQ40", "EQ50", "EQ60"],
	"S09": ["EQ61", "EQ62", "EQ63", "EQ64", "EQ65", "EQ66"],
	"S10": ["EQ67", "EQ68", "EQ69", "EQ70", "EQ71", "EQ72"],
	"S11": ["EQ73", "EQ74", "EQ75", "EQ76", "EQ77", "EQ78"],
	"S12": ["EQ79", "EQ80", "EQ81", "EQ82", "EQ83", "EQ84"],
	"S13": ["EQ85", "EQ86", "EQ87", "EQ88", "EQ89", "EQ90"],
	"S14": ["EQ91", "EQ92", "EQ93", "EQ94", "EQ95", "EQ96"],
}

static func supported(version: int) -> bool:
	return version == 1

static func item_count(version: int) -> int:
	return V1_PRICES.size() if supported(version) else 0

static func maximum_level(version: int) -> int:
	return V1_UPGRADE_COSTS.size() if supported(version) else -1

static func item_price(id: String, version: int) -> int:
	return int(V1_PRICES.get(id, -1)) if supported(version) else -1

static func set_items(id: String, version: int) -> Array:
	return V1_SETS.get(id, []).duplicate() if supported(version) else []

static func upgrade_price(level: int, version: int) -> int:
	if not supported(version) or level < 1 or level > V1_UPGRADE_COSTS.size(): return -1
	return V1_UPGRADE_COSTS[level - 1]

static func sell_price(id: String, level: int, version: int) -> int:
	var base := item_price(id, version)
	if base < 0 or level < 0 or level > V1_UPGRADE_COSTS.size(): return -1
	var total := base / 4
	for index in range(level): total += V1_UPGRADE_COSTS[index] / 5
	return total
