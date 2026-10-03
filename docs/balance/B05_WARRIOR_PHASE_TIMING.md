# B05 warrior phase-timing audit

Date: 2026-10-02. Scope: read-only analysis of four existing native live-scene fights. No engine reruns, player/actor edits, controller changes or balance changes were made for this audit. The only new files are this report and its [machine-readable evidence](evidence/b05_warrior_phase_audit.json).

## Result

Lower shared Boss HP does not imply a shorter individual fight. Archive5 seed1001 has a verified phase/action-selection discontinuity, a longer root detour and a lost hit chain. Neither archive satisfies every-seed60–90s acceptance.

| Shared Boss archive | cHP / cAttack | Warrior seed1001 | Warrior seed1004 |
|---|---|---:|---:|
|4|9.0 /1.0|87.3500s|93.0833s, fails|
|5|8.5 /1.0|92.3000s, fails|83.1000s|

All are CH01/class6/G2/D4. HP is recorded only. All four win with unchanged lawful loadout, owned items, manifest, talents, branches, resolved player stats and skill definitions. Recorded combat-source hashes differ only in `scripts/combat/enemy_calibration.gd` between archives; the two archive4 source manifests are identical. These are native60Hz active simulation seconds, not rendered real-time human gameplay.

## Verified seed1001 sequence

1. The first50 direct-hit audit entries have identical time, source, rawX, attack ID, target template, confirmed result and pre-hit chain. Boss startingHP is719,280 versus679,320.
2. LowerHP crosses P2 at29.6833s instead of30.2000s. In archive4 a P1 growth-rings warning starts30.1833s; phase entry then clears it. Its action index has already advanced. Archive5 enters P2 before that attempt.
3. Consequently archive5's first P2 warning is pod-rain at30.8667s, released31.9667s. Archive4's first P2 warning is growth-rings at31.3833s, released32.5333s. This follows the production phase/selector ordering, not a changed controller or random reassignment of stats.
4. Archive5 records a dodge at30.9167s and resumes root targeting31.8500s. Per-second positions show backward displacement from x892 at31.0167s to x639 at32.0167s, then return toward the right-hand root. The warning and dodge are recorded; the controller prioritizes visible danger over the counter target.
5. Archive5's last hit before the detour is BossW at29.6667s, leaving chain50. The next confirmed hit is root2 at34.2833s: a4.6167s gap and chain0. Production chain expires after4s. Archive4's BossQ at30.1833s is followed by root2 at32.5000s, a2.3167s gap; its chain survives. There are no chain resets in the other three audited fights.
6. Archive4 root2 takes three basics at chain52/53/54, consuming3,243/3,256/2,178HP. Archive5 takes four at chain0/1/2/3, consuming2,574/2,587/2,600/916HP. Both roots have8,677HP; last-hit figures are capped by remainingHP. The reset demonstrably reduces each uncapped basic's chain multiplier.
7. Root2 is destroyed at33.3000s versus35.4833s. Boss direct damage resumes34.9333s versus37.0667s. First chain100 occurs58.1000s versus90.4500s. The mean pre-hit chain count across Boss direct hits is67.53 versus44.10; this is descriptive, not a time-weighted damage attribution.

| Seed1001 phase | Archive4 seconds | Archive5 seconds | Difference |
|---|---:|---:|---:|
|P1|30.1833|29.6667|-0.5167|
|P2|28.4333|34.4167|+5.9833|
|P3|28.7333|28.2167|-0.5167|
|Total|87.3500|92.3000|+4.9500|

The phase-residency sums match the total time within floating-point rounding. P2 is where the added total time accrues: archive5 consumes less BossHP there (232,572 versus251,257) but takes5.9833s longer. The recorded loss of chain bonus and extra root travel are verified mechanisms. The exact number of seconds attributable solely to each is not established without a controlled counterfactual; do not label all4.95s as a measured chain-only penalty.

## Exclusions and limits

- No longer immunity window: all four record attackable time equal to total time; phase-shift residency is the same2.3667s. The B05 phase transition does not grant invulnerability. Non-invulnerable does not mean the player is in melee range or free to attack.
- No lost accepted skill damage in these fights:43/45/45/43 paid releases for archive4seed1001/archive4seed1004/archive5seed1001/archive5seed1004 respectively; every release matches a same-time, same-slot confirmed Boss direct hit. The three recorded cancellations all occur after their release. Direct-hit audit has zero unconfirmed rows. This does not prove every possible cast can never miss.
- Seed1001 basics all have direct hits: archive4's106 requests comprise96Boss+10root hits; archive5's108 comprise97Boss+11root hits. Collateral add hits are additional targets, not additional basic requests.
- Same durability obligations: each sample consumes26,031rootHP and25,216addHP; Boss healing and shield consumption are zero. Seed1001 heart-exposure duration is12.05s in each; archive5 actually deals more during it (95,206 versus79,873). More root durability or less exposure does not explain the slowdown.
- Resource deferrals increase in archive5seed1001: E7→15, Q5→8, W4→6, R23→23; empty-resource time0→0.5s. But all accepted spells release, R remains three casts, and the divergence/root detour occurs at990–1000rage. This rules out resource shortage as the initiating P2 detour cause; later deferrals can contribute but are not individually timestamped.
- No simple unlucky-crit explanation: seed1001 original Boss packets have36/139crits in archive4 and38/142 in archive5. Basic crits26→28, W5→5, Q3→3, E2→1, R0→1. Critical timing/value changes after the paths diverge, so counts alone do not isolate critical damage. They do not support a blanket drop in crit frequency.
- Archive4seed1004 has no chain reset yet fails93.0833s. Thus avoiding this one reset is insufficient for all-seed acceptance. Its P1/P2/P3 durations32.3833/30.9667/29.7333s versus archive5's32.1833/25.5833/25.3333s establish a real opposite-direction pair, not a contradiction in clocks.

## Minimal next measurement

The2×2paired seed/archive comparison is already complete. No rerun is needed merely to reconstruct it. Do not discard either failed seed or fit a single linear HP-to-TTK prediction.

For any next experimental sharedHP coefficient, first measure unchanged CH01class6G2 seeds1001+1004 and CH02class6G2 seed1001 as the upper/lower-time sentinels; include CH03candidate1 seed1001 before expanding. Retain exact phase/action order, root targeting/dodge decisions, consecutive confirmed-hit gaps, chain resets, releases and every failed outcome. A shared coefficient is still experimental until these and the required wider seeds/builds pass. These data justify neither a precise successful next coefficient nor a broad class buff, altered fixture/controller, skipped root or disabled mechanic.

## Sources

Raw report paths are relative to the checkout parent. Full-file SHA256 values and selected exact events are in the linked JSON.

- `_test_output/B05/20261002T165553503247Z-69633afb/observations.json`: archive4seed1001.
- `_test_output/B05/20261002T170650716503Z-7948206f/observations.json`: archive4seed1004.
- `_test_output/B05/20261002T171019210042Z-ed711d00/observations.json`: archive5seeds1001+1004.
- `scripts/combat/b05_boss_brain.gd:26–33,58–69,78–106`: phase check, clearing the current attempt and indexed next-action selection.
- `scripts/combat/hit_chain.gd:4–6,34–39,45–65`:4s expiration,+0.5%per hit,100cap and one confirmed increment per original attack.
- `tests/support/s11_battle_controller.gd:24–62,124–159`: visible-danger priority, root targeting and actual requests.
- `tests/test_b05_balance_matrix.gd:366–373`: phase/state and non-invulnerable-time counters.
