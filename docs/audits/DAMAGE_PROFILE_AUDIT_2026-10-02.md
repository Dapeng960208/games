# Damage/profile audit — 2026-10-02

## Scope and outcome

Audit bases: B05 `45fa857` and B06 `261f86a`, before the subsequent pressure/role policy changes. No damage, defense, growth or calibration values were changed by this repair.

Both directions use `scripts/combat/damage_resolver.gd`: corresponding armor/MR, physical corrosion before flat penetration, denominator 1000, one independent DR bucket capped at 0.65, then integer rounding. `enemy.gd` copies the already resolved profile without repeating level/difficulty/elite factors; `health.gd` only subtracts the final amount. `run_controller.gd:damage_player` adds equipment and contextual DR once, then consumes shield and HP.

A dedicated actual-actor audit on the B06 checkout exercised both chapters' ordinary/elite/Boss profiles at D4 through `MineEnemy`/`MineBoss.take_damage`, real receipts/CombatHealth, and `SalvagerPlayer.receive_damage`: 30 checks, zero failures, no script errors. It isolates settlement and is not a natural-combat or AI acceptance run. Run `20261002T230213804571Z-afb0b18c` retains its output; scratch scripts are not production assets.

Examples, no shield/status effects:
- Lv21 warrior armor440: B05 ordinary basic1280→889HP, elite1433→995HP; B06 ordinary1463→1016HP, elite1638→1138HP, all `round(raw*1000/1440)`.
- Player raw1000 with armor penetration30 / magic penetration10 against D4 ordinary armor210/MR160: physical847, magic870, true1000. Elite MR200 gives magic840. B06 Boss armor/MR170 gives physical877, magic862.
- No evidence from these cases of ineffective resistance, double difficulty/elite factors, wrong integer subtraction or zero-damage packets. This is bounded evidence, not proof every conditional ability is correct.

## Reproduced JSON API defect and narrow repair

`Numbers.ordinary("B05-M01",25,4,"normal")` and its elite equivalent survive default JSON serialization with a last-binary-bit change to `recovery_seconds` (both print `1.00877192982456`). The strict validator rejected the legal restored profile, and direct `Numbers.skill_damage` returned -1.

Important limit: production `Skills.freeze_damage` reconstructs canonical numerical values from ID/level/D/calibration before calculating its packet. The audit does **not** establish lost production attacks after restoration, nor explain the fresh D0 naked-clear result. That earlier impact hypothesis was withdrawn after tracing the complete command path.

Repair: only `move_speed` and `recovery_seconds` may match by their exact default JSON representation. No epsilon is used; all combat integers and identities still require exact equality. Type checks reject malformed motion values without a GDScript invalid-comparison error. The actual numerical formulas are unchanged.

Regression `tests/test_b05_profile_json.gd`: all 18species ×3levels ×5difficulties ×2ranks plus 5 Boss profiles; direct API parity, real frozen command positive damage/parity, changed HP/attack/defenses/level/D/motion rejection, malformed motion rejection, forged command attack rejection. 10875 checks, zero failures, no SCRIPT ERROR/ERROR in each checkout.

Evidence:
- Original minimal B05 failure: `20261002T225805510893Z-a364a2a5`; B06 copy: `20261002T225750488721Z-9c50e7a2`.
- Initial expanded regression exposed malformed string comparison errors plus a test-only absent Boss timing-key assumption; this run is not counted as passed (`20261002T230110152002Z-f46cb042`). Both were addressed before final runs.
- Clean B05: `20261002T230238842663Z-e503d90f`; clean B06 copy: `20261002T230257148479Z-77f2de6b`.

## Separate true-damage semantic question, not repaired

`b06_enemy_runtime.gd:filter_damage` applies BO06 frontal-shell ×0.65 even when damage_type is true. A1000 true packet becomes650, whereas a side packet remains1000. B05's root-protection multiplier in `b05_boss_brain.gd:incoming_damage_multiplier` is likewise applied by `boss.gd:take_damage` before the shared resolver and has no damage-type argument.

Shared numerical documentation says true damage bypasses resistance and DR while retaining immunity and CombatStatus shields, and permits weakpoint amplification. The chapter-specific shell/root contract must be checked before deciding whether these region/mechanic reductions are intended exceptions. No production change was made to this question; its direction cannot explain excessive naked durability.
