# B05 strength acceptance: staged live-scene evidence

> 开发检查点分发说明：本文是历史测量/结论记录。下述旧批次完整逐帧明细未随本检查点分发；仅保留历史结论、可复现测试代码、配置和当前archive15完整证据。省略文件及原Git对象哈希见 [检查点范围清单](PR7_DEVELOPMENT_CHECKPOINT_2026-10-03.json)。未分发不表示验收通过，也不表示源文件已删除。


Status: **in progress; not balanced/accepted**. No production stat tuning. B06 is blocked on complete authored enemy attacks, actual Boss integration, and lawful Lv30 progression/equipment. B06 tide/contact fixtures are not strength evidence.

## Current confirmed target (2026-10-02 16:31:36 UTC)

**This supersedes every earlier target below:** D4 G2 standard builds for all three classes must win with every tested seed in60–90active seconds. EndingHP is recorded only, with no acceptance floor. Other qualities are comparison/stress groups; no ordinary-room TTK target was specified. Candidate3 mage306.73s therefore definitively fails the current upper bound. No new class-stat change has been applied.

Durable numerical evidence is under `evidence/b05_runs/`; `index.json` hashes every retained versioned report. It contains source/snapshot/build identity, seeds, clocks, outcomes, damage receipts, resource/cast traces, and invalid-row flags. Screenshots, profiles, and console dumps remain outside this formal evidence set.

## Historical target (2026-10-02 16:03:07 UTC)

The user replaced the old35–50s Boss target with **at least60s**. There is no newly specified upper TTK limit. The conflicting lowG2≤60s upper bound is superseded; survival, HP and P5 relative comparison requirements remain. Historical baseline JSON retains the original gate used when launched, and must be reinterpreted against this revision. Full-matrix expansion is paused for damage/proc/controller audit before calibration; fixtures stay frozen.

## Frozen fixture and clock contract

`evidence/b05_frozen_builds_v1.json` contains all 27 B05 manifests, generated and legally validated before the first fight. SHA256: `80764812c1725c953470956616fb0e2f6ee31ffac35df83a6d5ed2284538f6ad`.

- Lv25/ilvl25; all three classes, class6/shared2, class4/shared4, shared6/class2; G2/P5/lowG2 definitions and deterministic legal affix filtering follow the inherited calibration document. Explicit class-policy-v2/generator-v3 eligibility fields are synthetic fixture provenance, not a claim of naturally acquired items or payment history.
- The exact new-level talent and 4+4 slot decisions were unspecified. These are **lawful test choices, not user-confirmed optimal builds**: physical mastery7/precision7/dexterity7/agility3; mage mastery7/precision7/dexterity7/vitality3. All spend24 with cap7. Branches Q-B/R-A.
- Recommended class6 shared slots: warrior feet/ring; gunner chest/legs; mage chest/feet. Shared6 retains class hands/weapon. Class4 shared slots are head/chest/legs/feet. No outcome-driven replacement.
- Counterplay prioritizes visible danger and active root wells. Actual move, dash, skill, attack and interaction APIs execute; actors, cooldowns, costs, AI, healing, shields, roots and weakpoints remain real. Mage submits zero basic attacks. No damage overrides, resource resets, external relics, potions, pre-stacks or invulnerability.
- Native60Hz/time_scale1 active-game seconds include approach, phase immunity, movement, mechanics, recovery and healing. `--fixed-fps60` advances the simulation faster than host wall time; these numbers are **not elapsed human gameplay seconds**. Every row records both clocks. Rendered real-time confirmation remains separate.
- Each batch has source hashes, engine log, raw packets, casts, phase/counter histories, per-second snapshots, actual actor roster and a checksum comparison against the pre-combat manifest. Managed isolated profiles and `/tmp/games-godot.lock` serialize bounded engine use. Zero process exit only means harness integrity, not balance acceptance.

## Early findings

| D4 class6 G2 | Seeds | Alive wins | Median active TTK | Median ending HP | Gate |
|---|---|---:|---:|---:|---|
| CH01 warrior |1001–1010|10/10|20.7167s|100%|FAIL: below revised60s|
| CH02 gunner |1001–1010|10/10|13.0750s|96.8829%|FAIL: below revised60s|
| CH03 mage |1001–1010|10/10|35.3167s|88.5288%|FAIL: below revised60s|

All three class6 G2 groups fall below the revised60s floor. Their sustained output differs substantially. One shared Boss parameter set must work across classes; the prior mage upper-bound concern is obsolete because the user did not set a new upper bound. No tuning has been applied.

The first exploratory run had a stale headless painted-backdrop adapter signature. Its figures were not accepted. A dedicated test-only two-argument adapter fixed it; the clean pilot reproduced the same outcomes. Accepted physical groups have no script errors, no failed harness checks and no source changes during their runs.

Managed evidence (relative to the shared checkout parent):
- `_test_output/B05/20261002T155823244647Z-c9e63f96/pilot.json`: clean three-class pilot; exploratory/probe=true, excluded from full acceptance.
- `_test_output/B05/20261002T160011013241Z-40eece7a/`: pinned warrior group;209 checks, no errors;64.60 host seconds including setup.
- `_test_output/B05/20261002T160129932348Z-71cc9432/`: pinned gunner group;209 checks, no errors;45.29 host seconds including setup.

## Remaining acceptance boundaries

Required matrix is27 groups ×10 seeds=270 Boss fights. Three groups are complete at this checkpoint. P5 pairing, lowG2, other mixes, ordinary/elite six-room D0–D4 coverage, prior-chapter gear entry, isolated P3 single-packet tolerance and representative rendered real-time confirmation remain open. No numeric ordinary-room clear-time ceiling has been invented. Skipped natural-phase casts are recorded, not credited as observed attacks.

Run a bounded group with `python tools/balance/run_b05_acceptance.py --hero CH01 --mix class6 --sample G2`. The runner enters the managed lock/profile wrapper automatically. Use `--room=L25 --difficulty=0 --seeds=1001` for an ordinary-room pilot, `--p3 --seeds=1001` for a separately labelled synthetic-phase single-packet test, and `--rendered --real-time --seeds=1001` for actual rendered timing. Directed P3 figures never enter baseline TTK gates.

## Packet audit before calibration

Transparent `b05_balance_observed_room.gd` records pre/post state around the existing direct-hit method, without calling modifier/proc previews twice. The same seed1001 outcomes reproduced after adding the observer. All58 identified direct Boss packets reconstruct exactly: warrior17/17, gunner23/23, mage18/18; no repeated attack IDs for those direct Boss packets. This is bounded evidence, not an exhaustive proof for every possible status/target combination.

Gunner's first R packet is11,407, correctly explained by rawX3080 + consumed hunter mark2566, damage bonus33.2% (25.2%gear+8%SG2), one1.5crit,1.02hit-chain factor,1.15root-heart exposure, and1000/(1000+160) defense, with the production integer boundaries. The next R pellets do not consume the mark again. Additional0.65H passive bonuses also match their recorded ready/consume state. Each native R pellet has its own attack_id while crit is rolled once per cast, as authored.

Baseline BO05 HP is an explicit design value, not a fallback: `b05_enemy_numbers.boss` resolves1000×1.35×10×1.48×4=79,920. Armor/magic resist are160. Seed1001 all three consume exactly79,920BossHP. Root durability is separately accounted (physical17,354; mage26,031); it is not added twice. Effective Boss healing and shield consumption are both zero in these samples. Actual summons, root DR and heart exposure remain active.

Warrior equipment follow-up damage612 and mage three bloom packets1016 each are recorded at proc_depth1. They do not produce duplicated direct-hit IDs. Mage field/status/equipment packets without direct attack IDs are treated as derived events, not automatically called duplicates merely because IDs are absent.

## Shared durability candidate2 (unaccepted)

The existing immutable calibration snapshots now support a B05 archive, with baseline archive1 unchanged. Candidate2 is **only** selected by `--candidate-b05`, a valid isolated profile, and `--b05-balance-candidate=2`. No normal launch or old adventure is opted in. All classes and D0–D4 share cHP4.4; baseHP1000, attack, defenses, skills, warnings and phase mechanics remain unchanged. D4 HP351,648.

| Seed1001 G2 class6 | Active TTK | EndingHP | Revised result |
|---|---:|---:|---|
| Warrior |49.8833s|100%|Fails60s floor|
| Gunner |35.7333s|89.6912%|Fails60s floor|
| Mage |145.1667s|53.2705%|Fails60%HP floor|

All three runs are clean with unchanged fixtures and controller. This is a failed candidate and a real cross-class survival tradeoff. There is no upperTTK failure assigned to the mage. Its4,758HPloss/10,182maxHP consists of sixgrowth-ring followup hits(2,412), sixroot-line hits(1,990), and one season followup(356), with zero effective healing or shield absorption. Resource-zero time0.75s understates cost pressure: E194/Q131/W314/R682 controller deferrals;85accepted spells, only1R in145s. No resource-reset or controller reprioritization has been used to conceal it.

Candidate evidence directories:
- CH02: `20261002T161229550015Z-20817db0`
- CH01: `20261002T161313509611Z-8c3aea42`
- CH03: `20261002T161336952415Z-3d6e2971`

All reside under the shared `_test_output/B05/` directory. Initial candidate invocations rejected a strict in-memory int-vs-JSON-float dictionary comparison before recording fights. The protocol check now normalizes runtime snapshots through JSON before equality; it does not bypass value validation. Those zero-fight rejected runs are not evidence. The dedicated calibration test verifies immutable archive1, candidate2, rejection of unarchived coefficients, and unchanged attack/defense/skill damage through D0–D4/P1–P3.

The duration gate now uses **minimum** standard-group TTK≥60s, not just the median, to avoid hiding any below60s seed. All median, minimum and maximum measurements remain reported. Historical runner summaries written before the user's revision retain their original gate field and are explicitly superseded by this report.

### Mage rotation decomposition

Candidate2's unchanged-controller, read-only ability-timeline replay (`20261002T161918106036Z-d20b1664`) reproduced the exact same145.1667s and53.2705%HP. All85paid spells released; none canceled.84timelines ended naturally; the lastW killed the Boss during recovery. Q42/W25 each had confirmed direct-hit roots.17E casts include12 explicit remote-node decisions: sevenE roots hit directly, while node detonations are separately classified and delivered57,564damage across19targets/packets. It would be incorrect to label every remoteE without a body-radius hit as a wasted cast.

| Phase | Active duration | BossHP consumed | RootHP consumed | AddHP consumed | PlayerHPloss | Paid spells |
|---|---:|---:|---:|---:|---:|---|
| P1 |41.6667s|106,183|8,677|0|1,027|Q12/W8/E6/R1|
| P2 |51.9500s|122,970|8,677|25,216|1,785|Q14/W9/E6|
| P3 |51.5500s|122,495|8,677|0|1,946|Q16/W8/E5|

Current Q-B range350/cost120/CD2.79; W range360, immediate110radius burst/cost200; E body155radius/cost200; R range420/cost500/CD29.76 with branchA lifetime7s all match current runtime design. The frozen controller uses actual definitions for legality. It retains an older node-placement preference (visible safe node spot, future velocity heuristic) and remote detonation opportunity, but these are optional legal tactics, not hidden production damage prerequisites. Its ten rejected node-placement opportunities are visible in the report. No post-outcome controller priority/cost/fixture change is used to make calibration pass.

The accepted diagnostic conclusion is a real encounter/player-output mismatch under the disclosed fixed policy, with mana-cost pressure rather than canceled/missing accepted spells. Candidate3 therefore tests a **shared** cHP9.0/cAttack0.35 (D4HP719,280), leaving each skill's timing/coefficient and every class's build/cost unchanged.600active seconds is an explicit observation timeout, not an invented upper balance target. It remains unaccepted until its actual seeded comparisons and survival gates are complete.


### Candidate3 integration failure quarantined

The first candidate3 pilot and next gunner batch are invalid in full, including TTK. `freeze_damage` originally rebuilt the baseline instead of the run's frozen calibration; changed actor attack made that seam return an empty command. The initial100%HP result was investigated immediately, exposed the missing command execution, and was never accepted. Their batch summaries are explicitly marked invalid while raw reports remain intact. Candidate2 has baseline attack and is a valid historical failure.

The correction passes the immutable snapshot through both command freeze and numeric-profile validation. A new regression demands a positive actualP3 frozen damage packet under candidate3; the live harness transparently records actual `_execute` commands and rejects missing execution or nonpositive offensive damage. Fresh pilots are required. Numeric snapshot comparisons normalize int/JSON-float token types while retaining exact value checks.

### Corrected candidate3 pilots (still unaccepted)

After the command-freeze fix, seed1001 results are:

| G2 class6 | Active TTK | EndingHP | Actual command evidence |
|---|---:|---:|---|
| Warrior |87.3500s|98.2937%|105harness checks; positive offensive command validation|
| Gunner |67.7333s|88.6945%|126harness checks; positive offensive command validation|
| Mage |306.7333s|62.0605%|206harness checks; positive offensive command validation|

The mage duration is5.11minutes of active simulation, with a narrow survival margin. This is a visible tradeoff, not hidden by medians or a new upper bound. No group is accepted from one seed.

Evidence: corrected CH02 `20261002T162558627102Z-c6980eeb`, CH01 `20261002T162628172509Z-bb3264eb`, CH03 `20261002T162702619944Z-567561c7`. A separate candidate3 P3/no-shield mage sample `20261002T162639427838Z-3042e36b` receives exactly one native CrownSweep packet: raw590, post-defense211HP,2.0723%maxHP, alive. No temporaryDR, dash or invulnerability. This proves actual changed attack reaches the damage receiver; it does not count as a baseline victory or TTK sample.

Final aggregation uses the explicit `combat_source_sha256` manifest in each protocol: numerical config/snapshot, all nonexcluded scripts (actors, AI, runtimes, controller, collision geometry, progression/save logic), and harness/fixture sources. The full source manifest is retained too. One reviewed headless-only noncombat exclusion is `scripts/world/b05_floor_repair.gd`: it only creates Sprite2D/shader materials from read-only geometry, and its sole creator is the native MineBackdrop replaced by this headless harness. It has no collision/actor/AI/save writes. The corrected gunner pilot saw only that visual file change; the dependency review cleared it while preserving its original hash and edit record. Rendered runs do not use that exclusion.

## Confirmed mage diagnosis and isolated player candidate1

The exact306.7333s mage ledger closes without an unexplained mana source:

`1200 initial +20984 effective regeneration +4400 class refunds +1620 SM4 refunds −28100 paid costs =104 final`.

There were44native100-mana spell-weaving refunds and27native60-mana SM4 refunds, all with zero basics. Attempted regeneration21,055lost only71to cap. The new zero-basic passive is functioning; neither missing refunds nor excessive overcap explains the gap. After10s every1Hz sample is below the500-manaR cost(max326);85.9%are below200. The fixed legal E→R→W→Q policy greedily spends lower-cost opportunities and never banks enough for anotherR. This is a disclosed controller/resource interaction, not evidence that a human can never castR.

The sustained BossHP rates in corrected shared candidate3 are warrior8,234/s, gunner10,619/s and mage2,345/s. Physical basics contribute324,687/719,280warriorHP damage and454,432/719,280gunnerHP damage. Mage has no free-basic stream. Required rootHP is26,031for each class, only3.6%of719,280BossHP; it does not explain the4×output gap. Costs/CDs bound how much regeneration alone can improve throughput.

### Exact opt-in change

`--mage-balance-candidate=1`, together with the valid isolated B05 candidate profile, freezes these fields into the run stats:
- **Spell H ×2.5**, after the original integer `AD+0.7AP` resolution. It applies consistently to direct spells and their H-based node/field damage against all targets, not only this Boss/chapter. AP, basicH and relicH remain unchanged. Fixed-AP equipment procs are not multiplied.
- **Base mana regeneration80→160/s**. Maximum/starting mana1200,0.25s post-cast delay, skill costs/CDs and100/60refund triggers remain unchanged.
- HP, armor, magic resistance, healing and shield calculations are untouched. This is not an AP multiplier and does not multiply survivability sources.

The numeric hypothesis was roughly1.5×more affordable casts combined with2.5×spell output, covering the observed3.5–4×gap. It is a test candidate, not a released global class redesign. The pure contract checks levels5/10/15/20/25 and verifies unchanged basics/relic power/defenses/capacity/costs and single H multiplication; real earlier-chapter balance remains untested and is an adoption prerequisite.

The initial invocation exposed a candidate-only propagation omission: player `_power_snapshot` omitted the new marker, so regeneration changed but liveH remained2329. That run(`20261002T164517916234Z-8ad3d1de`) is flagged **not valid for the full candidate** and retained as a labelled regen-only ablation:158.4167s,6Rcasts. The corrected path propagates the frozen tag and asserts liveH5823 before combat. With the full candidate and Boss archive3, seed1001 wins68.7167s. No faulty result is substituted for the corrected one.

### Restored authored Boss attack: archive4

Since the user removed remainingHP gates, cAttack0.35was no longer needed to satisfy that obsolete target. Archive4 retains sharedcHP9.0 and restores authoredcAttack1.0, without changing warnings, immunity or phase mechanics.

| Seed1001 G2 class6 | Mage candidate | Active TTK | EndingHP (record only) |
|---|---|---:|---:|
| Warrior |not applicable|87.3500s|95.1140%|
| Gunner |not applicable|67.7333s|75.7866%|
| Mage |candidate1|74.6000s|78.5307%|

Evidence: CH01 `20261002T165553503247Z-69633afb`, CH02 `20261002T165634057647Z-c206b58d`, CH03 `20261002T165041486020Z-3cdcbecb`. MageQ27/W19/E12/R3, no cost deferrals, no basics, all mechanics active. These three pilots fit60–90s; **one seed is not the required full-matrix acceptance**.

## Naked negative controls

Naked fixtures use realLv25, the same24talents andbranches, all eight slot strings empty, zero owned/equipped items, no relics/potions/buffs/resets/invulnerability. The initial profile with an empty dictionary was correctly rejected by production validation; the lawful representation has all eight empty-string slots. No combat from the rejected profile is counted.

Active combat uses the fixed10Hz visible-danger decision policy, native navigation/attacks/spells/dash and legal counterplay. These are automated active-avoidance samples, **not face-tanking**. Pressure is a separate one-real-actor fixture with no offense/defensive input; it omits the authored director and is never called a full room clear.

| Sample | Active time | Outcome | EndingHP |
|---|---:|---|---:|
| Baseline naked mage,L25 D0 authored five-enemy/two-wave group |16.4500s|room cleared;zero effective hits|100%|
| Baseline naked warrior,L25 D0 group |16.7333s|room cleared|100%|
| Baseline naked gunner,L25 D0 group |10.9667s|room cleared;diagnostic due concurrent archive file edit|84.7902%|
| Baseline naked mage,L30 D0 later group |36.4333s|room cleared|57.0664%|
| Baseline naked mage,one realLv25M01 standing pressure |14.4500s|dead;6effective hits,2243actualHP consumed|0%|
| Mage candidate1,naked,L30 D0 later group |16.1333s|room cleared|92.1088%|
| Mage candidate1,G2,L30 D0 later group |10.4500s|room cleared|100%|

This establishes that naked actors are vulnerable when hit, but the current legal avoidance/output policy can clear both an introductory and a later room. It does **not** prove whole-chapter naked viability. Candidate1 makes the later naked clear faster/safer, so meeting the Boss clock alone is insufficient for adoption. A dedicated continuous native route test with carriedHP/resources and level-matched entry fixtures is in progress. Native relic-skip healing, if encountered, must be recorded separately, not silently removed or called no-heal survival.

No exact numerical threshold for “quickly” was supplied. No equipment-state auto-kill, unavoidable attacks, hidden Boss-class scaling or gear admission rule has been added. Any eventual vulnerability tuning must preserve legal counterplay and derive from real base/equipment/attack pressure relationships.

### Base versus equipment: avoid a false “gear adds little” conclusion

`evidence/b05_mage_base_equipment_breakdown.json` freezes the same naked/G2 mage's resolver values, equipment contributions, talents, branches and source run IDs, both authored and candidate1.

| Stat | Naked(base+same talents) | Gear contribution | G2 resolved |
|---|---:|---:|---:|
| AD |266|0|266|
| AP |817|2130|2947|
| HP |2243|6634flat,plus14.7%HP bucket|10182|
| Armor |180|1551|1731|
| Magic resistance |468|1551|2019|
| Mana capacity/entry |1200|0|1200|
| Authored regen |80/s|0|80/s|
| Candidate1 regen |160/s|0|160/s|
| Authored spellH |838|1491effectiveH|2329|
| Candidate1 spellH |2095|3728effectiveH|5823|

HP resolves once as round((2243+6634)×1.147)=10182; the percentage contribution is not counted twice. G2has4.54×HP,2.78×spellH, and3.48×precrit direct spell damage after its25.2%damage bonus. Naked sets are empty, every equipment contribution is zero, and there are no owned/equipped items. Its legal talents remain active by design.

Thus a16s-versus10s short-room clear does not establish nearly equal damage power: small enemy HP is capped by overkill, travel and finite-wave timing also consume the clock, and the controller actively avoids damage. The mana engine is essentially base-driven: capacity/regen are the same, with equippedSM4 adding only its actual qualifying refunds. A principled equipment-contribution adjustment should be considered only after continuous-route/control-policy evidence, not an automatic naked damage penalty or an unsupported broad reduction of base stats.

## Seed boundaries and the frozen shared-durability scan

Archive4 fails warriorseed1004 at93.0833s; its passing87.35s seed1001 cannot conceal that. Archive5(cHP8.5/authored attack) changes which seed fails: warrior1001=92.30s,1004=83.10s; gunner1001=62.65s; mage-candidate1=76.9667s. Archive6(cHP8.3/authored attack) yields warrior1001=90.15s,1004=84.65s; gunner1001/1008=64.5667/62.60s; mage=72.25s.90.15s remains a failure.

The independent [warrior phase audit](B05_WARRIOR_PHASE_TIMING.md), with four-case [numeric evidence](evidence/b05_warrior_phase_audit.json), confirms a legitimate phase/action discontinuity: an earlierP2 transition changes pod-rain scheduling, causes a backward dodge/root detour, and a4.6167s confirmed-hit gap drops chain50. Archive4's2.3167s gap retains it. Missing releases, immunity residency, extra root/addHP or worse crit frequency do not explain that case. Another93s failure occurs without a chain reset, so removing this one interaction would not establish acceptance. No combo-window, controller, phase or counterplay change is authorized by these findings or applied.

`evidence/b05_durability_scan_v1_plan.json` freezes a small grid: cHP8.2/8.3/8.5/8.7/8.9/9.0, authored attack, unchanged class6G2fixtures/controller, warrior1001+1004, gunner1001+1008, mage-candidate1/1001. Known clean rows are reused only with exact archived factors, build checksum and controller hash; full original source manifests are retained. New points8.2/8.7/8.9are fixed before those new runs. Each short class batch owns and releases the managed engine lock. `b05_durability_scan_v1_results.json` is explicitly partial until all five sentinels at each sampled point complete. A sampled passing point is not a proven continuous interval or the required full seeded/mix matrix.

The only clock-comparison tolerance is1microsecond for floating serialization, far below one60Hz frame; it cannot turn90.15s into a pass. EndingHP is record-only. No large full matrix is being run on a known-failed candidate.

## Continuous naked-route evidence

The dedicated [continuous report](B05_NAKED_CHAPTER_2026-10-02.md) and [selected numeric evidence](evidence/b05_naked_chapter_v1.json) are authoritative for carried-state chapter attempts, separate from independent room starts.218checks pass across the bounded controls:
- Lv21baseline: diesL27,68.483s,6effective hits,14kills.
- Lv25baseline: diesL27,95.967s,7hits,22kills.
- Lv21candidate package(mage1/Boss archive4): diesL29,73.633s,7hits,33kills.
- IndependentLv21L30baseline: clears9enemies,35.683s,51.074%HP.

Native transitions preserve player identity and HP/resource. All empty slots, zero equipment contributions/sets/procs/refunds and zero mage basics are verified. Native relic-skip healing remains real and separately recorded(240HP inLv21baseline versus360HP inpaired candidate). The candidate advances farther but does not clear the chapter in this seed. Other classes/seeds/difficulties and human play remain untested, and “quickly” has no approved numerical cutoff. The naked vulnerability requirement therefore remains a separate unaccepted judgment, not a silent equipment-state punishment.


## Completed class6 seeded boundary check, 17:55 UTC

The six-point scan completed all30sentinels. Only sampled cHP8.7 passed its five sentinels; this was overturned by the subsequent full class6G2seed range. `evidence/b05_matrix_c7_m1_class6.json` contains30/30rows, all alive victories:

| Class | Minimum active seconds | Maximum active seconds | In60–90 |
|---|---:|---:|---:|
| Warrior |81.4667|95.6000|7/10|
| Gunner |62.6833|67.0167|10/10|
| Mage candidate1 |70.2333|89.0333|10/10|

Warrior1005=92.0167,1007=95.6000,1008=93.8333 are explicit failures. No remaining-mix/quality matrix expansion is justified on this known-failed candidate. RemainingHP is record-only. Full victory/mechanic checks remain in force. Neither the class6sample nor this scripted strategy establishes all-build or player-play acceptance.

`evidence/b05_matrix_c7_m1_hash_manifest.json` lists every run's explicit source SHA256 manifest. Cross-run differences are the visual-only floor overlay (absent from headless dependency set, present in graphical run) and the newly added but never loaded counter-sensitivity controller in frozen scenes. The frozen controller, numerical tables, loaded actors/brains, gear/talents, collision/runtime and save dependencies are unchanged. No whole-worktree dirtiness shortcut is used.

### Actual rendered, normal-speed reference

The candidate7/mage1class6G2seed1001run `20261002T175107015979Z-4a9c77db` used actual production backdrop, Godot4.6.3, X11/OpenGL3 compatibility and Mesa25.0.7llvmpipe(LLVM19.1.7software renderer). It completed98checks without failures:79.9000active game seconds,81.102334host combat seconds,69.7309%remainingHP. Whole-process startup/test runtime92.4849s is separate. Its active clock equals the headless fixed60Hz run for this seed. Start/end captures were outside the combat clock; the automated input policy remains identical. This proves a normal-speed rendered execution, not hardware GPU acceleration or human play. Numeric rendering/clock metadata are retained; screenshots remain disposable managed output, outside source/evidence commits.

### Fastest versus slowest frozen warrior

At identical695,304BossHP,26,031required-rootHP and25,216addHP, seed1009 has P1/P2/P3=31.3833/27.6167/22.4667seconds;1007 has30.0333/38.2500/27.3167. Thus the14.1333second total spread is concentrated inP2(+10.6333) andP3(+4.85), not added encounterHP. All41/47paid skills respectively released. The slow row has a4.1333second confirmed-damage gap entering the second root and sampled chain52→2; fast row has no sampled reset and maximum gap2.55seconds. There is no demonstrated missing-paid-skill defect.

The frozen physical controller intentionally attacks required roots with basics. Real players can use skills there. Separate, predeclared sensitivity policies therefore test three fixed seeds(1001reference,1007slowest,1009fastest) without overwriting frozen results: all_skills permits the sameE/R/W/Qeligibility against roots; q_approach permits legalQapproach outside basic range but reservesR. Both preserve normal aiming, costs, cooldowns, movement/collision and warning avoidance. They are diagnostic experiments excluded from the frozen matrix, not a post-hoc acceptance-policy swap. See `evidence/b05_warrior_counter_sensitivity_v1.json`.

The two sensitivity batches are clean (271/244checks). For seeds1001/1007/1009, all_skills gives93.5500/84.2167/93.0833seconds; q_approach gives89.9333/87.0833/93.5500. All survive. There is no sub60counterexample among these six diagnostic runs, but both policies still exceed90. Improving one seed changes phase timing and can worsen another; merely allowing root skills is not a demonstrated fix.

A bounded **proposal, not implementation or acceptance** is an isolated warrior spell-damage-channel×1.20 candidate with sharedBoss8.7 retained. Skills account for51.9744%/52.7405%of slow/fast warriorBossHPdamage, so a static same-events estimate adds10.39%/10.55%total output (95.60→86.60s and81.4667→73.69s). This estimate deliberately does not claim real phase/mechanic periods shrink proportionally. It could be disproved by the next actual runs. Such a candidate must apply consistently to actual warrior combat, without changing AD/AP, basics, shields/heals/defenses, costs/cooldowns or the4second combo window; it requires ordinary/naked/earlier-chapter checks before adoption. There is no demonstrated bug authorizing a silent controller or class-mechanic correction.

Manifest limitation: historical per-run hashes included gameplay scripts, data, fixtures and controllers but omitted scene/project files. A supplemental post-run scene/project hash record and Git diff against the original frozen baseline show no changes to those files. This is explicitly post-run verification, not a retroactive claim that they were hashed before each fight. The runner now includes scene/project dependencies prospectively.

Precision note: the frozen warrior uses Q-B, which removes Q displacement and uses a135-radius impact. The historical experiment name `q_approach` means casting Q at its legal edge outside basic range while approaching on foot; it does not mean a Q dash. No branch was changed.

## Warrior skill-output candidate1: rejected pilot

The separately authorized isolated candidate applies×1.20only to warrior skillH at all levels/targets. Defaults remain unchanged; no Boss-class resistance, basic, resource, defense, shield/heal coefficient or4second chain changes. `b05_warrior_candidate1_plan.json` freezes five sentinels before runs. Pure default/candidate contracts atLv5/10/15/20/25show identical complete resolved stats after removing the two candidate tags; only skillH changes, with native integer rounding. LiveG2skillH2056→2467, basicH2056 unchanged.

Actual seeded times1001/1005/1007/1008/1009are94.0833/81.7333/87.8667/83.2667/88.5500s,5/5alive,405checks pass. Seed1001fails90s, so the full ten-seed expansion is stopped. ItsP1/P2improve to26.6667/33.5500s, butP3grows to33.8667s. A7.6333s original-direct-hit gap during pod_rain→three_roots and repeated legal evasions approaching the third root drops chain65; ongoing periodic damage does not refresh it. All45paid skills release. Static throughput estimates did not predict this discontinuity. **Candidate not adopted; further class-damage scanning paused.**

Independent naked warriorLv25D0L30seed1001risk pair: authored31.85s,9kills,99.7396%HP; candidate29.75s,9kills,99.8698%HP. Both clear all native finite waves and destroy the root. Authored receives2actual M02hits; candidate1. Each native packet is464raw→312after defense, with307absorbed by a normal8%-maxHPshield and5HP lost (Q-B and the three-basic passive both have that capacity; original receipts cannot uniquely attribute the source). Effective healing0in both. Candidate does not increase shield magnitude. These are legal avoidance/shield samples, not standing tanking or whole-chapter clears. They still caution against declaring gear dependence solved simply because a Boss timing sample passes.


## Naked warrior chapter counterexample supersedes mage-only reassurance

Default Lv21warrior/D0route seed1001 clears the native chapter in258.7500active seconds, with2668/3450HP,18effective received hits,100checks and no failures. It remainsLv21throughout; all8slots/equipment contributions/sets/refunds stay empty. Actual HP ledger is3450−945+163(native relic-skip healing)=2668. Shared shields absorb4431of5376post-defense incoming damage. An append-only guard-source receipt observer exactly reproduces the original outcome and attributes2370absorption toQ-B,1509toE,552to the three-basic passive; no overlapping pool is counted twice. See the updated naked report and `b05_naked_warrior_equipment_dependency_v1.json`.

At the sameLv21authoredL25entry, a separate stationary/no-input pressure control dies after21.4500s/12hits to realM01+M02, without kills, shields or healing. Thus legal avoidance/normal class shields and naked base durability are separate concerns. The negative control is unpassed; one seed proves a counterexample but not a reliable-clear probability. No further class-damage scan is justified by the rejected warrior candidate. No naked equipment-state penalty or unavoidable attack was introduced.

## B05 ordinary-pressure archive10: rejected

Only ordinary/elite attack×1.35 was tested; Boss/body/class/gear/shield values remained authored. Earlier archives remain immutable. EntryLv21stationaryL25death improves21.45s/12hits→17.75s/9hits, but normal naked warrior still clears the native chapter258.6667s/2443HP/18hits. Ledger3450−1807+800native relic-skip healing=2443; shields absorb5422. Thus this is another rejected equipment-dependency candidate, not a fix.

Paired three-class/class6/G2/L30D0seed1001runs all clear: warrior16.40s in both, HP99.4423%→99.2509%; gunner8.75s and mage12.0333s unchanged, both zero-hit/fullHP. Character output candidates are off in this ordinary-pressure comparison. It does not establish allD0–D4, elite or priorgear-entry acceptance. Rank-based ordinary factors also apply consistently to ordinary summons; no claim that all indirect Boss pressure is unchanged.

The new attack factor exposed an integration-only int64 overflow in the old multiply-before-reduction helper. The initial306failed checks produced no combat measurements. Cross-canceling numerator/denominator factors before multiplication preserves one final rounding and fixes it. All540species/level/difficulty/rank calibration/serialization combinations pass; existing authored enemy-number399checks and combat836checks also pass. Real pressure command damage is positive. Old snapshots retain baseline values.

Formal result: `evidence/b05_ordinary_pressure_candidate10_results.json`; next-choice brief: [Equipment dependency proposal](B05_EQUIPMENT_DEPENDENCY_PROPOSAL_2026-10-02.md). Any baseHP/shield-to-equipment redistribution remains unapproved and unimplemented. Further damage scans are paused.
