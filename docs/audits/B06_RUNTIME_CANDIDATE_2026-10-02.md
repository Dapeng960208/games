# B06 candidate runtime checkpoint

Scope: current `docs/levels/06_TIDAL_CORAL_CITY.md`, not the archived PR5 draft. Default chapter registration, persistent progression, equipment catalogs and old save schemas stay unchanged.

- Seven frozen geometry definitions compile into production room layouts through an explicit `b06_candidate` context. Every declared dry corridor is tested at full 180 world-pixel width; all patches together occupy at most 65% of the floor. Drain approaches and entries/exits remain dry. Blueprint 2800×1800 maps by 0.58.
- Actual MineRoom, MineEnemy, CombatHealth, CombatStatus and SalvagerPlayer now support an opt-in tide host. High water gives ordinary sea actors a non-stacking 10% shell, +12% movement and player -15% movement. Room ordering owns time. Gate interaction uses real range and line of sight; damage, departure and pause interrupt without consuming cooldown.
- Pure checkpoint restore preserves tide phase, gate cooldown and stable actor admission history, cancels stale held interaction, and rejects cross-room state. This is an isolated candidate checkpoint; production combat save schema has not been extended, and full mid-combat enemy/guard restore is still pending.
- Candidate encounter plans cover all 18 identities across six ordinary rooms, at fixed chapter levels and D0–D4. L36 has exactly three finite waves across two zones. Production director enforces six-per-zone and eighteen-per-room caps. Candidate enemies have no economic rewards and candidate clear never settles permanent progression.
- L33 alternates north/south patches by the saved fixed cycle; L35 bell previews the fixed upcoming direction without advancing time. Bell preview is retained in the candidate checkpoint, with invalid payloads rejected atomically.
- Completion of all authored ordinary skills, difficulty additions, support objects, full boss attack acceptance, full navigation playthrough, native art admission and legal Lv30/equipment strength are NOT completed by this checkpoint. The first eight implemented ordinary species use their authored executor after checkpoint54446d3; remaining contact-only candidates explicitly carry `b06_candidate_contact_only`; their legacy generic brain is not acceptance evidence for authored skills.

## Focused evidence

Official Godot 4.6.3, managed `tools/test_workspace.py --biome B06`, shared engine lock, explicit `--test-profile=user://test_b06_tide_live.json` and isolated per-run XDG directories. No player profile is used.

- Geometry: 39 checks, 0 failures.
- Tide adapter + production CombatStatus: 33 checks, 0 failures.
- Actual MineRoom/player/enemy tide and six-room finite encounter traversal: 225 checks, 0 failures. Enemy removal in this deterministic test is fixture cleanup, not natural combat balancing.
- Full project headless editor import passed before live checks.

Natural combat, visual acceptance, balance matrix and release remain pending. Preserve the previously authored tide/boss state foundation limits; do not claim checkpoint counts prove completed chapter gameplay.

## BO06 actor/brain increment

An explicit BO06 candidate now uses the real MineBoss factory with a dedicated B06 brain, resolved B06 profile, and the room's existing tide object. `B06BossState.configure_shared` binds that object; neither the actor nor brain adds a tide timer. Authoritative actual health drives 70%/40% transitions. P3 preserves clock start and gate state. Cast and hit admission both protect the full 2.5-second post-high output window.

Claw-to-pillar exposure verifies the released cone origin/direction/range/angle against fixed pillar centers and room LOS, then checks completed linked drainage and the shared12-second cooldown. Cast receipts expire after16seconds, so deduplication cannot permanently exhaust reusable pillars. The120-degree claw cone and520-world-pixel cannon reach are explicit candidate geometry choices pending gameplay review.

The BO06 brain freezes warning geometry and sequences each multi-part action through its own tell/lock. Dual cannon retains the first target axis and mirrored100-pixel muzzle offset. Stage intervals are minimum0.8/0.8/1.2seconds for cannon/bombard/pincer; existing shared V2 warning compression is applied once by the skill builder. It uses no artificial TTK wait or new HP multiplier.

Focused actual-host D0–D4 boss suite:94checks,0failures. Includes MineBoss/brain factory, profile HP applied once, phase/tide continuity, nontracking claw, second cannon warning, output protection and JSON checkpoint restoration. Pure tide/boss-host44 and pure boss-state59 checks pass. These are deterministic mechanics tests, not natural survival or damage/TTK acceptance. Latest required G2 standard-build boss TTK is60–90seconds across all three classes; remainingHP is recorded only, not an acceptance gate. Naked fixtures use normal level/talents with empty gear, relics and external buffs; ordinary groups must pose rapid lethal pressure rather than allow stable clears. No old35–50target or unverified B05 HP multiplier is applied.

Still pending: actual whole-action damage/counterplay sampling for all six boss moves, safe dry-island bombard admission, complete mid-combat actor/brain/runtime save restoration, candidate exit UI traversal, all18ordinary skill completion, native asset pose admission and lawful Lv30 strength tests. Default BossLayouts rejects BO06 unless its explicit candidate argument is true. Candidate clear and actors remain economy-blocked.

Next room-host work: nearest dry point within70world pixels, authored tidal direction query, safe physical coral-wall admission excluding180-wide routes/gates/exits, banner shield extension contract, and frozen pending cast/actor restoration. Coordinate these narrow interfaces with the ordinary combat implementation rather than sharing mutable geometry.

## Room admission and traversal increment

BO06 shell bombard now constrains the entire90-radius warned footprint outside a permanently dry90-radius refuge plus18px player clearance, before warning publication. Both stages use the same constraint. Expanded boss command/phase tests cover all six difficulty-gated actions:186checks passed. Bounded dry-retreat and authored tide-direction helpers plus120px wall admission preserve all180px dry corridors and68px gate/bell/exit approaches. Helper suite:55checks passed. Common room collision and navigation consume the combat runtime's live-wall queries without mutating the static layout.

A new explicit candidate traversal controller follows L31–L36→BO06 via actual exit interactions. It has a separate clear-boundary JSON format and refuses live actors/effects there. Full hostile-combat restoration is a separate format under development; unsupported player casts/projectiles/deployments are refused explicitly rather than discarded. Candidate exit routing must never call the production expedition completion transaction.

### Verified candidate checkpoint boundary

Clear-boundary traversal:77checks passed, including seven actual F exits, JSON node-index canonicalization, duplicate exit rejection and unchanged production profile/expedition dictionaries. The separate hostile snapshot reconstructs ordinary/Boss actors and breakable anchors with fresh instance IDs, restores HP/status guards, frozen brain warnings, finite runtime effects, encounter progress and the same tide phase. Focused20checks passed with a live mine/anchor and atomic rejection of invalid HP. Active player movement, cast/basic/dash buffers, knockback, player projectiles and deployed hero objects currently reject capture/restore; this is explicitly not complete player-action save support or production save activation.

All candidate formats require an explicit isolated test_b06 profile and keep economic reward settlement disabled. The closed combat codec rebases references through stable IDs, never loads scripts or resources named by a snapshot, and rejects unsupported objects. Reconstructed actor profiles are checked against current authored numerical profiles. Full suspended player-action restoration and broader interrupted-save/fault injection remain pending.

Same-instance BO06 reconfiguration now resets its finite escort ledger and single tide clock; phase transitions preserve the escort budget. Expanded actual boss suite:189checks passed,0failures. No player cooldown or resource reset is introduced by phase changes.

### Native body/prop visual check

Actual MineRoom captures at2560×1440 used llvmpipe/OpenGL, an explicitly candidate floor layer and real BO06 EnemyVisual + gate/pillar drawing. Source body height stays207world pixels across poses; collision remains60radius. Idle/high-water screenshots were inspected; no body clipping or dry-core obstruction was observed in these views. They show debug-like rectangular water overlays and do not establish final environmental polish, GPU performance, all-camera navigation, or full floor acceptance. Default floor runtime readiness remains false. Screenshots and output JSON stay outside Git and formal code backups.

## Save scope clarification

The authoritative B06 chapter document requires fixed tide-phase persistence (line110) and restoration that does not skip the warning (line112). It does not require suspended player-cast, projectile or deployment replay. Existing production and B05 `combat_snapshot.gd` lines3–9 explicitly define safe-boundary snapshots and exclude positions, pending attacks, projectiles and target-bound counters; `run_controller.gd` accepts checkpoint saves only in safe/cleared phases. Development standards also clear queued inputs on pause and room/UI transitions.

Therefore full in-flight player restoration is not a B06 completion gate. The compatible production extension is an optional versioned B06 tide/mechanism payload at existing safe boundaries, preserving remaining phase/drain cooldown and avoiding repeated entry effects or rewards. The isolated hostile-combat serializer is a diagnostic facility only, not a replacement production save format. Its refusal of unsupported player actions is intentional and must not cause unrelated game-engine expansion. Production payload admission is coordinated with gated B06 progression; old snapshots and release gates remain unchanged.

## Existing Main and safe-boundary progression integration

The isolated process gate now requires debug plus both `--candidate-b06` and one strict `--test-profile=user://test_b06_candidate/<name>.json`; duplicate paths, traversal and competing B05/B06 flags reject. Shipped numerical JSON remains4chapters. Reviewed B05 candidate infrastructure was ported narrowly fromc1ecf0a, with the already verified beacon/finite-wave/boss-entry/canonical-ID fixes retained. No B05 art or experimental calibration was copied.

B06 registers six ordinary rooms,18 species and BO06 behind that process gate, retaining BO05 as prerequisite. Legacy version-one routes retain only the original four-region descent ring. New single-biome routes introduce L31–L36 in order before reusing late rooms. D3+ replaces one final-zone heavy with an elite without increasing concurrency. Real registered route contexts are distinct from economy-blocked diagnostic previews.

The production `CombatSnapshot` accepts one optional versioned `b06_mechanisms` payload through the existing safe-boundary contract. It validates room/difficulty/tide/drain/phase, restores remaining warning time, cancels held interaction, and preserves old payload-free/B05 snapshots. Actual tide live tests:231checks; original combat snapshot regression:136checks; both passed.

Three actual Main/camp/room/extraction runs completed with real finite-wave deaths, BO06 death, v4 loot receipts, keep decisions, per-room disk reloads, exact tide-phase resume and repeated-settlement/extraction rejection. Final clean-exit counts: CH01=218, CH02=218, CH03=216, all0failures, no SCRIPT ERROR/ERROR or resource-leak warning. The test initially omitted freezing Main's music updater during cleanup; it now uses the existing bounded cleanup pattern and did not change production audio code.

B0635-template registration has real base-item stats and class policy3; set/unique effects remain explicitly pending. B06 shop/craft choices are hidden because no creation-economy version is approved, and existing creation UI caps its current V3 contract at25 even for higher-level candidate heroes. No B05 equipment substitutes for B06 extraction. Natural combat balance and full set-effect strength remain pending; see [effect implementation handoff](../implementation/B06_EQUIPMENT_EFFECT_RUNTIME_PLAN.md).

Final closed-gate regression: B06 default-gate suite6checks and original route suite365660checks passed,0failures. The route fixture's stale36-species expectation was updated to the existing54-species four-chapter catalog, matching the reviewed B05 fix; no default gameplay catalog expansion was introduced.
