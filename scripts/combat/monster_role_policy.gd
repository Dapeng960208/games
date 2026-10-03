extends RefCounted
## Archived ordinary/elite candidate policy. Input is the canonical v1 integer
## baseline, never an actor already scaled by this policy. No player reads.
const VERSION := 2
const BASE_PERCENT := 150
# HP, actual damage stat, armor, magic resistance. Exactly one role branch.
const SPECIALIZATION := {
    "tank":[120,100,115,115],
    "output":[100,115,100,100],
    "skirmisher":[110,105,100,100],
    "support":[110,100,110,110],
}
const FIELDS := ["max_hp","damage","armor","magic_resist"]

static func role(archetype: String, authored_role: String) -> String:
    # Authored tank/support identity wins over attack geometry (e.g. M54 is
    # artillery but a tank; ranged healing must never become burst output).
    if archetype == "tank": return "tank"
    if archetype == "support": return "support"
    if archetype in ["caster","assassin"]: return "output"
    if archetype == "skirmisher": return "output" if authored_role in ["R","ranged","artillery"] else "skirmisher"
    return ""

static func apply(baseline: Dictionary, archetype: String, authored_role: String) -> Dictionary:
    if baseline.is_empty() or baseline.get("rank") not in ["normal","elite"] or baseline.has("monster_role_policy_version"): return {}
    var identity := role(archetype,authored_role)
    if identity.is_empty(): return {} # Unknown roles fail admission explicitly.
    var result := baseline.duplicate(true)
    for index in FIELDS.size():
        var key: String = FIELDS[index]
        var value: Variant = baseline.get(key)
        if not (value is int or value is float) or not is_finite(float(value)) or value != int(value) or value < 0: return {}
        # Archived v1 integer × base × one specialization, rounded once here.
        var numerator := int(value) * BASE_PERCENT * int(SPECIALIZATION[identity][index])
        @warning_ignore("integer_division")
        result[key] = (numerator + 5000) / 10000
    result["monster_role_policy_version"] = VERSION
    result["monster_role_specialization"] = identity
    return result
