# B06 equipment runtime slice · 2026-10-02

## Result and remaining decision

The 15 authored class-set/shared-set/unique effects now have real reducer and actor integration. The shared SU6 damage branch is enabled for uniform fixed power orientation only. Mixed physical/magic SU6 has no defined source-P selector in the approved contract: its token remains unconsumed and it emits neither damage nor speed until that rule is confirmed. This is a partial implementation boundary, not a proposed balance rule.

This slice does **not** establish G2/P5 strength, three-class 60–90s BO06 acceptance, natural acquisition balance, hardware performance or full visual acceptance. Candidate routing remains opt-in. Reward probabilities, authored enemy/Boss HP, immutable acquisition versions, item fingerprints, and saved player data are unchanged.

## Runtime changes

- `b06_equipment_effects.gd` extends the existing deterministic reducer. Confirmed HP/shield loss commits hit effects; immunity previews, repeated event IDs, derived packets and failed/free paid-cast counters cannot produce extra triggers.
- SW2/SU2 use a bounded received-distance modifier. Tide movement admits the reduced vector with the original collision radius. Damage knockback applies a distance scale instead of changing its decay law. U01 changes only terrain-slow magnitude (.85 becomes .88).
- SW4 uses the W's actual paid cost. SW6 uses the machine contract's confirmed Q/W hit with a saved forward origin/direction, range120 and maximum3 targets.
- SG2 uses the first confirmed W target. SG4 consumes real Q displacement and marked W contact. SG6 owns a weak target mark and one R root: only actually created first-three projectile objects receive frozen target-specific supplemental packets. The normal hit pipeline confirms contact before supplemental non-recursive damage.
- SM2 changes only committed W immediate burst radius. SM4 distinguishes immediate burst from lingering nodes and shares a single bonus across that burst's targets. SM6 counts successful paid Q casts and owns a bounded .8s delayed ring with frozen origin/power and maximum4 targets; room change/rebind removes it.
- SU4 keeps remaining combat period in the existing serialized cooldown map; room entry cannot mint a free shield, and swap cannot reset cadence. SU6 receives source-local absorbed/expired shield-ending events even when a larger pool remains. Unequip removal does not emit that event.
- U02 increases received healing at the existing settlement seam, retaining ordinary grievous-wound reduction and integer rounding. U03 uses the actual completed drainage receipt; a button press, cancelled/out-of-range/dead channel, and the informational tide bell do not qualify.
- Historical snapshot modifier keys remain accepted. New B06 passive keys are optional on read. No target WeakRef, pending shot or timed ring is serialized across safe boundaries; existing global cooldowns and SU4 period remain.
- Runtime registry text now describes implemented behavior while preserving the immutable acquisition catalog. SU6 mixed-orientation limitation is explicitly shown. One coordinated visual-only change uses amber for native-water warning outlines.

## Focused evidence

All checks use `tools/test_workspace.py run --biome B06`, with isolated profiles and the manager's single engine lock. No extra engine lock, production save or remote push was used.

| Test | Result | Scope |
|---|---:|---|
| `tests/test_b06_equipment_effects.gd` | 204 checks, 0 failures | Actual 1/2/3/4/5/6/8 thresholds, three-class 4+4/6+2/2+6, fixed power, repeated/derived/free/failed events, paid counters, source endings, R ordinals, period/rebind |
| `tests/test_b06_equipment_effects_live.tscn` | 161 checks, 0 failures | Actual casts/projectiles/actors, immunity and shield-only contact, cancellation, frozen delayed ring, pause/resume, period JSON restore, source-specific shield expiry/break, actual .88 terrain speed and32px reduced push, interrupted/range/death/completed drainage |
| `tests/test_b06_equipment_r_live.tscn` | 61 checks, 0 failures | Independent actual first-three projectile payloads and confirmed extra health loss equal to0.12P, only marked target gets second damage packet, fourth/unmarked round gets one, repeat callbacks, cancelled unfired rounds, room/rebind cleanup |
| `tests/test_combat_snapshot.gd` | 136 checks, 0 failures | Existing snapshot migration/validation compatibility |
| `tests/test_b05_equipment_live.tscn` | 73 checks, 0 failures | Existing B05 live class/shared/unique equipment regression |
| `tests/test_b06_main_progression.tscn` | CH01/CH02/CH03 each216, total648 checks, 0 failures | Full Game progression, safe snapshots, rewards, room reloads and extraction after equipment integration; not strength acceptance |

Godot4.6.3 headless logs were checked for script/resource errors, not merely exit status. Test artifacts remain in the managed B06 output directory and are not committed. The R-specific two-file test is a separate responsibility commit following this implementation.
