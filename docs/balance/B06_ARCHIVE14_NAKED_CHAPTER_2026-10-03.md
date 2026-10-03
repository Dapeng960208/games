# B06 continuous naked chapter observation — archive14

## Scope and outcome

Three lawful Lv26 entrants, difficulty 0, seed 1001, continuous production route transactions in the unified B05 source after merge `8988632`. All three naturally died before BO06. This satisfies the narrow negative observation for these three automated attempts; it is not proof for all seeds, alternate talent choices, human play, or all controller policies. Immediate death or first-room death is not required.

Frozen production model: `aca0c65e05481015029a17789905b1d66efbdd86`, archive14 numerical policy version 3 and separate Boss policy version 2. Test implementation: `59f2ac2`. No production values, damage, actor health, spawning, or movement rules were modified.

## Method

- Start through `Game.start_run` and use `ExpeditionController` candidate/preflight plus `Game.choose_expedition_node` / `Game.advance_expedition_node` native transactions.
- Every advance requires the native room reward/completion receipt. Required enemies/objectives are cleared by normal skills, basic attacks for physical heroes, movement and dash. No forced hits, lethal fixture, teleports, forced completion, room skips, or direct HP/resource writes during combat.
- Same player and run cross rooms; absolute HP, resource and cooldown preservation are asserted at every transition.
- Frozen lawful talents: mastery 8, precision 8, dexterity 8, agility 1 (warrior/gunner) or vitality 1 (mage); Q branch B, ultimate branch A. All 25 points legally allocated. Eight equipment slots empty throughout; no external relics, potions, purchases or equipment procs.
- Every relic offer uses the production skip API. Its native up-to-6%-max-HP healing is allowed and separately recorded; it is not represented as disabled.
- No field-item equip or keep decisions. Production automatically stages pending loot and it remains observable; it is not deleted to fake an empty inventory. All runs ended in native death settlement, so no extraction banking occurred.
- Controller reads visible threats and uses production requests at native 60-Hz physics / time_scale 1. Mage issues zero basic attacks. Read-only ability wrapper records actual paid commits and timeline; guard trail records shield source at actual damage receipt.
- Transitive source fingerprint covers 325 reachable scene/script/config/data/runner dependencies including shared_enemy_growth.gd. All three attempts have identical dependency fingerprints before/after, zero script errors and zero harness failures. Documents and unrelated test files are excluded.

## Results

| Hero | Active seconds | Natural death node | Kills | Effective hits | HP lost | Shield absorbed | Native skip healing | Basic shots | Checks | Paid casts |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| CH01 | 264.05 | 9 / L35 / objective | 45 | 21 | 5118 | 5752 | 1180 | 162 | 334 | 117 |
| CH02 | 114.42 | 7 / L36 / branch | 33 | 6 | 3038 | 0 | 700 | 199 | 204 | 58 |
| CH03 | 33.12 | 1 / L31 / branch | 4 | 3 | 2163 | 0 | 0 | 0 | 87 | 22 |

Warrior shield sources were only native hero_q, hero_f and hero_passive:three_rivets. Gunner and mage absorbed no shield damage. Combat-heal feedback and inferred in-room net healing were zero in all rooms; all observed HP increases were the separately recorded native relic-skip recovery.

## Per-room observations

### CH01

Managed evidence: `games-recovery/_test_output/B06/20261002T235528795924Z-597889d5/` (`protocol.json`, `observations.json`, `summary.json`, `engine.log`, isolated profile and native Godot log).

| Node | Room | Role | Seconds | Kills | Hits | HP loss | Shield absorbed | End HP | Outcome |
|---:|---|---|---:|---:|---:|---:|---:|---:|---|
| 1 | L31 | branch | 42.55 | 6 | 6 | 907 | 2149 | 3031 | native_room_cleared |
| 2 | L32 | branch | 28.38 | 6 | 2 | 439 | 630 | 2828 | native_room_cleared |
| 3 | L33 | objective | 29.47 | 6 | 1 | 77 | 315 | 2987 | native_room_cleared |
| 4 | L34 | branch | 32.77 | 6 | 4 | 1906 | 630 | 1317 | native_room_cleared |
| 5 | service_supply | supply | 0.02 | 0 | 0 | 0 | 0 | 1553 | native_room_cleared |
| 6 | L35 | objective | 30.52 | 6 | 0 | 0 | 0 | 1553 | native_room_cleared |
| 7 | L36 | branch | 65.77 | 9 | 6 | 1193 | 1398 | 596 | native_room_cleared |
| 8 | L35 | branch | 31.57 | 6 | 1 | 526 | 315 | 70 | native_room_cleared |
| 9 | L35 | objective | 3.02 | 0 | 1 | 70 | 315 | 0 | natural_death |

### CH02

Managed evidence: `games-recovery/_test_output/B06/20261002T235830992055Z-80334bca/` (`protocol.json`, `observations.json`, `summary.json`, `engine.log`, isolated profile and native Godot log).

| Node | Room | Role | Seconds | Kills | Hits | HP loss | Shield absorbed | End HP | Outcome |
|---:|---|---|---:|---:|---:|---:|---:|---:|---|
| 1 | L31 | branch | 25.78 | 6 | 2 | 1372 | 0 | 966 | native_room_cleared |
| 2 | L32 | branch | 14.15 | 6 | 0 | 0 | 0 | 1106 | native_room_cleared |
| 3 | L33 | objective | 20.07 | 6 | 0 | 0 | 0 | 1246 | native_room_cleared |
| 4 | L34 | branch | 17.83 | 6 | 1 | 671 | 0 | 715 | native_room_cleared |
| 5 | service_supply | supply | 0.02 | 0 | 0 | 0 | 0 | 855 | native_room_cleared |
| 6 | L35 | objective | 20.83 | 6 | 1 | 217 | 0 | 638 | native_room_cleared |
| 7 | L36 | branch | 15.73 | 3 | 2 | 778 | 0 | 0 | natural_death |

### CH03

Managed evidence: `games-recovery/_test_output/B06/20261003T000210013655Z-a4ead95d/` (`protocol.json`, `observations.json`, `summary.json`, `engine.log`, isolated profile and native Godot log).

| Node | Room | Role | Seconds | Kills | Hits | HP loss | Shield absorbed | End HP | Outcome |
|---:|---|---|---:|---:|---:|---:|---:|---:|---|
| 1 | L31 | branch | 33.12 | 4 | 3 | 2163 | 0 | 0 | natural_death |

## Reproduce

Run each hero as a separate managed batch from the unified B05 checkout:

```sh
python tools/balance/run_b06_naked_chapter.py --hero CH01 --seed 1001
python tools/balance/run_b06_naked_chapter.py --hero CH02 --seed 1001
python tools/balance/run_b06_naked_chapter.py --hero CH03 --seed 1001
```

The runner owns the managed B06 output and shared Godot lock; do not add an outer flock. Scene/autoload structure validation uses `--parse-only`. The default observation safety bound is 3600 active seconds, but none of these attempts approached it; each ended with genuine native death. A bound or navigation blocker would be inconclusive, not counted as negative-control success.
