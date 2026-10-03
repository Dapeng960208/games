# B05 combat integration and focused evidence

Scope: B05 ordinary actors B05-M01–B05-M18 and BO05 only. This is an implementation record, not a natural-balance or release acceptance claim. The authoritative design remains `docs/levels/NEXT_EIGHT_CLASS_GEAR_INDEX.md` and `05_BLOOMING_TREE_COURT.md`, not the archived proposal.

## Production seams

- `EnemyProfiles.resolve` dispatches exact B05 IDs to `b05_enemy_skills.gd` only for ruleset 2. `BossProfiles.resolve("BO05", D, 2)` resolves the independent frozen boss numbers. Original B01–B04 paths are unchanged
- `MineEnemy` selects the B05 FSM only for `B05-M` identities; MineBoss selects the B05 BossBrain subclass only for BO05. Registration/unlock/routes remain the room/content owner's responsibility
- The command builder owns D0/D2/D4 geometry, coefficients, names, tells and follow-ups. The brain publishes the same command through `current_skill/current_telegraph`, freezes at lock and releases it to the ordinary runtime
- Existing `enemy_warning_timing.gd` is the sole difficulty timing multiplier. The expressly authored 1.2-second dew channel and 1.5-second sunlight charge keep that total visible channel time, with lock included rather than appended. Root-control casts keep at least 1 second visible warning
- Active cooldown begins on release; direct interrupt spends half that active cooldown. Missing support/network targets cause ordinary 1.0a attacks or navigation. No permanently idle support state
- Runtime delegates B05 numerical packets to the frozen chapter factory and applies each coefficient, ordinary tier / boss phase and D skill factor once. It does not rescale integer actor A
- Every effect is bounded by the common 128 effects / 18 actors. B05 summoned M02 use half same-level HP, own the same room capacity, are unrewarding, and have two lifetime attempts of at most two live adds. Plant buds and seed shells are unrewarding destructibles
- Healing is one ally per cast, 6% maximum HP, actual non-overheal receipts, and a lifetime 25% external-healing cap per recipient. Bosses, objectives, anchors and self are excluded. D2 clears ordinary speed impairment, not elemental chill. D4 shield uses the existing shared-max pool
- Weaver sharing transfers one 20% packet under explicit `b05_share` kind, excluding re-entry and other derived damage triggers. Only one active pair applies to an incoming packet, and >300 separation or weaver death breaks it

## Room and player interfaces

`room.b05_mechanics` provides `connected`, `nearest_active_well`, `set_well_mode`, `boss_root_state`, `boss_phase_changed`, `all_wells_closed`, `constrain_enemy_command`, `constrain_boss_command`, and `can_enemy_cast`. Constraining must occur before warning, then the returned full command is frozen. A fixed safe route and the 30% area ceiling take precedence over a desired footprint. Active sunlight commands use `requires_sunlight`; the room can veto an uncommitted or delayed beam after a shade interaction.

A destroyed active well calls `boss.apply_arena_counter("b05_root_well", {well_id})`. Each new well receipt is one-use; exposure gives +15% incoming damage for 4 seconds with a 10-second trigger interval. Without exposure, a powered network reduces incoming damage by 35%. Rootwell HP cannot heal the boss. P1/P2/P3 thresholds are 70% and 35%, old uncommitted hazards are canceled on change, and the visible transition is 1.2 seconds. Opening 6 seconds allow only the sweep. Pod rain and transplant additionally begin at P2, and seasonal bloom at P3; difficulty gates are still required. Multi-part hazards leave a full 2-second approach window after their last segment.

Player control/equipment effects remain in the player lane. Combat emits `root` duration .6 / same-family protection 2 seconds, `slow` with multiplier .85 or .8, and persistent `notify_hostile_hazard(stable_id, inside, damaged)` events. Damage means the real receive path accepted HP/shield loss. Warning circles do not create those events. Destroyed finite enemy anchors report a player-attributed hostile-destructible event once; removal/cancellation does not count as destruction.

## Explicit implementation defaults where source was incomplete

These are first-implementation defaults approved for the implementation pass on 2026-10-02, not final user-approved balance targets. Existing source numbers always win. They live in `b05_enemy_skills.gd` and the B05 runtime extension, and are not a second numerical ruleset.

| Actor | Missing parameter resolved for implementation | Reason / safety |
|---|---|---|
| Common | Base lock .4s, reduced by the existing helper; ordinary support range 240 / link search 260 | Reuse warning family, no new compression factors |
| M01 | Sweep angle 2.1 radians; root line width30, 0 damage, duration2; end flower radius38 | Root-control line is not an unspecified extra damage packet |
| M02 | Small seeds radius30, ±80 offset, .45s after impact; .35s main seed flight; slow ×.8, .8s refresh | Finite two children, no child splitting |
| M03 | Moss width30/duration2/slow ×.8; slide .4s, harmless return hop .25s | Full 180 and 80 source distances; no return hit |
| M05 | Fence thickness24; D2 total length190 (110+40 each end) | Non-solid destroyable hazard cannot shut the only exit |
| M06 | Leaf range200/speed380; lunge .32s | One secondary leaf, fixed lock |
| M07 | Small flower radius38, offset135, D2 delay.45 / D4 delay.8 | Independent later hit, no same-frame D4 stacking |
| M08 | Self-shield duration5 | Ends with the bounded sharing window |
| M09 | Roll width44/radius24, .5s; one 110-long reflected leg .28s; final thorns radius38/slow-only2s | Only actual solid contact permits the shown second leg; no invented thorn damage |
| M10 | Residue is slow-only for2s; .5s refresh | Preserves authored .7a direct spray; no extra unseen damage |
| M11 | Shield push range110/120°; patch radius40/slow-only2s; shards radius80 with .6s warning | Shield mitigation35%, finite20%-HP block budget; no reflection |
| M12 | D4 harmless decoy radius55, offset150, sea-green edge | Decoy has no damage or dangerous red outline |
| M13 | Slam range115/angle1.6; one D0/D2 bud, two D4 buds; thorn line140×22, fires at2 and4 seconds | Each bud HP10%, lifetime4, no rewards |
| M14 | Beam width24; endpoint flower .4a; second beam .8s after first | 1.5s full visible charge; room shade veto remains authoritative |
| M15 | Root line length200×36; D2 two100 segments separated.6s | Network loss cancels remote vine; default90-range branch strike remains available |
| M16 | Fan ±22°, speed430/radius8; shell HP10% / lifetime3; outward explosion radius60/90° | Shell blasts point away from the safe fan gap; fan receipt cap2 |
| M17 | First ring65–130, then center65 after.65s; each uses1.25a; root shield1.3s | Distinct nonoverlapping first/second footprints; unpowered shield removed |
| M18 | Alternating shield/speed modes; speed8%; mark6s, next submitted attack adds.2a once; exposure+15%3s | Shared maximum shields; no simultaneous mode stacking |
| BO05 | Root lines360×32; rings150 then150–300; root tides160–230; summonCD20 | All footprint admission occurs in room before warning; 2 summon attempts remain lifetime-bounded |

## Native first-room poses

Exactly B05-M01/M02/M04 use `assets/generated/enemies/b05_poses_v1`: nine original 1254×1254 RGBA PNGs copied byte-for-byte and verified against the art manifest SHA-256. Each identity has idle/tell/execute source images, three separate textures. The fixed source anatomy height is reused across all poses; every pose has its own absolute foot/core/outlet. `EnemyVisual` uses the same foot-origin transform and mirror for the selected texture and visual outlet. It does not normalize every frame's crop or canvas, and does not modify collider/range.

Recovery/walk/recoil reuse the declared existing transforms; these three key poses are not a full walk animation or eight-direction bank. M04 extends its hands in the second part of the still-interruptible channel; M02's visual seed path starts at the selected execute pose's pod muzzle. Source art inspections and metadata tests are distinct from actual production 2K/camera/occlusion tests. `runtime_quality_gate_passed` remains false pending those tests. Original 54-body and 599-variant mappings are not rewritten.

## Evidence and unverified boundaries

First focused pass, official Godot 4.7.2, serial `nice -n 10`, no-autoload isolated project and isolated XDG data: `tests/test_b05_combat.gd` **813 checks, 0 failures**, clean engine log after fixing two detected implementation errors (reserved `_set` method signature and recursively inherited resin follow-up flag). This pass covers the actual common runtime with deterministic fixtures and all 18 types at D0/D2/D4, five-difficulty catalog/timing/numerical contracts, lifetime healing, nonrecursive share, interrupt CD, phase/root windows and finite summons.

Latest rerun after the pose/VFX and ordinary-slow integration refinements: **836 combat checks, 0 failures**, and `tests/test_b05_pose_bank.gd` **131 checks, 0 failures**, both official 4.7.2 exit 0 and no script/engine errors. The added checks cover the .35-second seed flight, real persistent-area entry/exit IDs, root shutdown canceling existing and delayed lines, ordinary-slow-only cleanse, front/flank mitigation, outward seed-shell geometry, one-use flower marks, nine independent source textures, fixed anatomy scaling and same-frame outlets in four aim directions. Source PNG SHA-256 hashes were rechecked unchanged. The pose checks use actual EnemyVisual transforms in a headless fixture and do not replace rendered-pixel approval. No complete natural B04→B05 playthrough, three-class TTK, S11 matrix, complete 18-monster art, BO05 final art, hardware GPU performance or full chapter acceptance is claimed here.

Graphical fixture prepared (not run by the combat lane): `tests/test_b05_monster_pose_capture.tscn`, using real MineEnemy/EnemyVisual/B05 brain and runtime on L25 with a fixed production camera. It writes eighteen 2560×1440 keyframes plus source-frame/outlet/HP metadata under ignored `artifacts/b05-monster-poses/`. Only the idle still is explicitly AI-paused; tells, seed flight, healing and attack releases advance the production paths. Runtime quality approval must follow inspection of those captures.

## Production-target regression discovered by the first 2K pass

The first graphical three-monster pass failed (124 checks / 32 failures) because B05EnemyBrain had assumed every victim exposed `is_alive`; real SalvagerPlayer owns life through Game.run and has no such method. The helper now matches the existing EnemyBrain has-method guard, while MineEnemy retains its outer Game.run HP/death check. All 32 capture assertions were downstream failures to enter a tell or release; those images are not acceptance evidence. A new real-node regression, `tests/test_b05_actor_live.gd/.tscn`, passed **41 checks / 0 failures**, official 4.7.2 clean exit 0: the three first-room actors at D0/D4 actually acquire the real player, release and damage/heal through production paths, and real BO05 acquires and damages that player. No player script was changed by this fix. The subsequent fresh graphical pass and remaining pixel issue are recorded below.


## Latest graphical evidence: 160 checks, 30 native captures

The final controlled graphical run passed **160 checks / 0 failures**, **18 principal 2560×1440 keyframes plus 12 same-state no-detail-card comparisons**. Rendering was Godot 4.7.2 OpenGL Compatibility on Mesa llvmpipe, not hardware-GPU performance evidence. The capture fixture now explicitly disables automatic EnemySkillRuntime physics and advances the complete scene through its manual test clock; every capture verifies that player HP and the runtime clock stay unchanged across render waits. Each case clears prior floating/contact feedback. The preceding 142-check captures did not freeze that independent runtime clock and are superseded for timing evidence.

Independent inspection of the latest no-detail M01 vine pose, M02 tell/left execute and M04 left/right channel representatives confirms the distinct native bodies and mirrored outlets are visible without the optional detail card obscuring them. M02's left and right execute records each show HP 100000, zero feedback events and a real seed in flight; its fixed-clock images show the seed between the native pod outlet and the locked target. M04's real healing record is 1637→1833, with the visible waterline aligned to the current channel outlet. Existing keyframe limitations remain: no authored eight-direction animation and no full walk bank.

**Pixel issue found and subsequently corrected:** the main M02 landing job retains the caster origin while common job drawing centers a circle on origin. Its fly-time orange area is therefore drawn at the gunner, although actual landing damage still resolves at the locked target and the pre-release tell correctly marks that target. The next isolated fix should set the landing job's display origin to its already-frozen target while keeping the native projectile visual start unchanged, then recapture that flight. This is a display/damage-geometry mismatch; This earlier run did **not** establish M02 landing-warning pixel acceptance. The 160 count verifies the stated fixture assertions, not this previously missing pixel condition. `runtime_quality_gate_passed` remains false; no complete B05 acceptance is claimed.

Evidence files remain ignored under `artifacts/b05-monster-poses/` and `artifacts/b05-runtime/monster-poses-gpu.log`. These generated captures/caches are not source assets. The formal source art, source hashes, authored foot/outlet metadata and tests remain the reproducible deliverables.

M02 landing-origin correction subsequently applied: the pending landing command now sets `origin = target` before its existing .35-second job is queued. The projectile visual still reads the original source command and native execute outlet; damage, locked target, coefficient and timing are unchanged. The exact live-node regression now passes **47 checks / 0 failures** (official 4.7.2, clean exit 0), including both D0/D4 real pending M02 jobs: the warning center equals the locked target, the collision footprint contains the target and does not contain the caster. The focused two-direction recapture subsequently passed **36 checks / 0 failures**, producing two real execute frames and two same-state no-detail comparisons. Both were visually inspected: the orange landing circle is centered on the frozen player target, separate from the caster, while the native seed remains between the current pod outlet and that target. The capture stores both warning center and locked target, as well as remaining flight time; no hit occurred merely from image encoding. This one-line fix is separate from the unintegrated readout and hazard-admission work.
