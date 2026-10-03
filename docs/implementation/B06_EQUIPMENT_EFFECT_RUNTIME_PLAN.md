# B06 equipment effects: implementation handoff

Status update (2026-10-02): **all35 templates have real candidate acquisition, qualification, item validation and extraction. The 15 effects now have focused runtime implementation; mixed physical/magic SU6 source-P selection remains pending an explicit decision.** See [runtime evidence and boundaries](../audits/B06_EQUIPMENT_EFFECTS_2026-10-02.md). The seam table below records the pre-implementation handoff requirements. A legal gold+2 loadout is an acquisition fixture, not strength acceptance. Do not tune boss HP or declare the three-class60–90s G2 target met using a fixture missing these effects. RemainingHP is recorded only. Naked controls require normal level/talents and no gear/relic/external buffs, with actual finite ordinary encounters.

Authoritative definitions: [current B06 chapter](../levels/06_TIDAL_CORAL_CITY.md#5-四套八槽装备), [shared class/gear contract](../levels/NEXT_EIGHT_CLASS_GEAR_INDEX.md). Machine-readable definitions remain `data/b06_equipment.json` and `scripts/core/b06_equipment_catalog.gd`; do not use archived PR5 drafts or rewrite the acquisition archive to add combat effects.

## Exact effects and missing seams

| Effect | Required behavior | Existing receipt / missing integration |
|---|---|---|
| SW2 | While the warrior E shield exists, forced displacement distance−25%; combined same-family reduction≤50% | Inspect live `hero_f` guard. `b06_tide_runtime.push_actor` currently passes no gear reduction to the existing `admit_push(...,reduction)`; wire a bounded received-displacement modifier. Do not alter collision radius or make permanent immunity. |
| SW4 | Within4s after E, first actual W hit refunds15% of that W's actual Rage expenditure; ICD8s; free W refunds0 | `player.gd` already emits paid `skill_cast`; `hero_abilities.gd` puts `paid_cost` on direct-hit context. Arm E window, consume only confirmed W hit, deduplicate multi-target W by cast root. |
| SW6 | After actual shield absorption, one counter-tide token; next Q/W within6s adds0.40P forward120-range wave,≤3 targets; ICD8s | `damaged` event already reports `shield_absorbed` and `e_shield_absorbed`. Need confirmed absorption token and bounded forward target selection/derived packet. No recursive equipment triggers. |
| SG2 | W main-target damage+8% | Existing root `first_target` and per-projectile hit receipts identify first real W recipient. Do not buff all penetrated targets or basic/child hits. |
| SG4 | After real Q displacement, within4s first W hit on a hunter-marked target reduces E remainingCD by1s; ICD7s | Existing `gunner_q_completed` reports `actual_distance`; confirmed-hit context includes hunter mark. B06 requires real movement, not B05's separate100px threshold. Failed/blocked Q cannot arm it. |
| SG6 | W actually penetrates2 distinct enemies: apply6s tide-mark to W main target; its next R's first3 actually fired rounds each add0.12P; once per R; ICD12s | Need stable W root + two confirmed distinct targets, main-target WeakRef mark, and explicit R shot ordinal/committed shot context. Current `skill:<serial>:<index>` IDs provide a source but should not be parsed as an undocumented protocol. Cancelled/unfired rounds cause no damage; no raised projectile cap. |
| SM2 | W immediate crystal-burst radius+10%; lingering node radius unchanged | `hero_abilities.gd` separates W `burst_radius` from node `radius`. Modify only the committed immediate-burst spec. |
| SM4 | Actual E hit arms next W immediate damage+12%, lasting6s; ICD8s | E is runtime slot `f`; use confirmed direct hit, not cast attempt. Need immediate-W-burst tag so persistent node ticks cannot consume/benefit. Multi-target initial burst shares one root bonus. |
| SM6 | After3 successful paid Q casts, next W adds a radius110 ring0.8s after its immediate burst,0.45P,≤4 targets; ICD10s | Existing successful paid `skill_cast` supports one count per cast; Q multi-target hits/auto nodes do not count. Add a bounded delayed ring in the loadout adapter, freezing original power/origin and retaining equipment-derived non-recursion flags. Do not require a preexisting node or basic attack. |
| SU2 | Forced displacement distance−20%; same-family total≤50% | Share SW2's explicit distance-reduction seam. Must work for all3 classes. |
| SU4 | Every12s in combat generate6%maxHP shield lasting4s; no free immediate room-entry shield; equipment change does not reset period | Add an independent combat period preserved across relevant rebind/room transitions. Do not equate this with an unconditional room-enter trigger or let repeated equip restart/mint shields. |
| SU6 | That SU4 shield naturally expires or is actually broken: next direct hit within6s adds0.25P single-target and grants8%movement for3s; ICD12s. Unequip removal does not trigger | Need source-specific shield-ending receipt with cause `expired`/`absorbed`/`unequipped`; current global `shield_broken` alone is insufficient when another larger shared pool remains. Consume on real direct hit only. |
| U01 boots | Terrain-slow magnitude−20%, total terrain reduction≤50%; tide displacement unchanged | Tide state already computes the correct .85→.88 movement result via `player_movement_multiplier(patch,.2)`; player stat bridge currently does not supply this gear value. Do not add20 percentage points or affect pushes. |
| U02 ring | After own shield actually absorbs damage, received healing+8% for4s; ICD12s | Existing actual `shield_absorbed` receipt can arm buff. Add a received-healing modifier at the existing healing settlement seam; exclude zero/rejected absorption. |
| U03 charm | Completing a combat mechanism interaction grants4%maxHP shield for3s; ICD15s | Tide host `drain_completed` emits only after0.6s valid range/LOS/alive channel. Route receipt to loadout; never trigger from F press, interrupted channel or UI inspection. Tide-bell preview is informational and needs an explicit choice before counting as a completed combat mechanism. |

## Smallest responsibility split

Shared integration needs **one owner** to avoid concurrent edits:

- `scripts/combat/equipment_effects.gd`: dispatch/state/CD/ICD and bounded modifier merge. Prefer a new `b06_equipment_effects.gd` helper rather than extending unrelated B05 branches.
- `scripts/combat/combat_loadout.gd`: build trusted B06 contexts, choose real targets, apply derived packets/healing/CD changes, own bounded delayed rings.
- `scripts/combat/player.gd`: source-aware shield receipt, received healing, successful cast/real displacement contexts. Preserve confirmed damage settlement.
- `scripts/combat/hero_abilities.gd`: immediate-W radius/damage tags and explicit emitted R shot ordinal; no fabricated future shots.
- `scripts/combat/projectile.gd` / `scripts/combat/room.gd`: preserve those contexts across actual hits; do not create a parallel hit pipeline.
- `scripts/world/b06_tide_runtime.gd`: consume received-push/terrain modifiers and publish completed combat-mechanism receipt.
- `scripts/data/content_registry.gd`: replace pending text/flags only for behavior actually implemented and verified.
- `scripts/combat/combat_snapshot.gd`: only necessary safe-boundary cooldown/period/source metadata. No general in-flight player serializer. Target-bound temporary marks and pending casts still obey existing room-boundary cleanup.

Parallel pure helpers/tests can be owned independently for warrior, gunner and mage/shared families. Agree event schema with the shared integrator first. Do not edit generator v4, class policy3, immutable archive templates or item fingerprints merely to add an effect; those were frozen and checked in43d7769.

## Required focused evidence

- Pure2/4/6 and mixed4+4/6+2 tests for all3 classes, including fixed physical/magic shared instances.
- Real actor confirmation: miss/immunity/shield-only hits, repeated hit IDs, multiple W targets, actual two-target penetration, blocked displacement, cancelled/unfired R rounds, paid/free Q/W, node ticks and derived damage non-recursion.
- Shield sources: absorbed versus naturally expired versus unequipped; multiple source pools; no free room-enter/gear-swap SU4 shield; period/CD remains stable across clean-boundary save/reload.
- Timed ring has frozen origin/power,≤4 targets, releases once after0.8s, and is removed on room departure under the existing boundary contract.
- U03 interrupted/out-of-range/dead channel does not grant shield; completed drainage grants once; U01 leaves tide push unchanged.
- Only after effects pass: lawful G2/P5/naked strength cases using actual18-species finite groups and actual BO06 phases/counterplay. Do not substitute raw stat arithmetic for runtime strength.
