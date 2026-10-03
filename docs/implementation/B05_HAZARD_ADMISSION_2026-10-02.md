# B05 whole-command hazard admission

Gated development increment; normal chapter count remains4. This closes the missing admission seam and is not full natural-combat or chapter acceptance.

## Contract

- One command and its authored followups are described together before warning/lock. Deterministic motion aftermath includes moss trails, leaf projectiles, rebound-thorn endpoints, buds and both outer M16 shell landing corridors. Projectile collision can settle shells early, so their possible landing corridor is protected instead of only their maximum-range endpoint.
- Lingering ground/control geometry cannot intersect the frozen180-wide main or140-wide safe corridor. A further14-world-pixel actor-contact margin makes this conservative for a character at its edge. Instantaneous melee/projectile geometry is area-budgeted without banning all attacks on a route.
- Conservative clipped polygon areas are summed against30% of usable room area. Overlapping commands do not earn a discount. Static obstacle areas are conservatively subtracted from the denominator. Rings are bounded by their full outer disk, not optimistically treated as an empty safe centre.
- Original geometry is tried first, then whole-command rotations. Only detached ground-area commands may translate; physical charges/projectiles/melee retain their origin. Child positions, directions, points and paths move together.
- A finite per-cast reservation survives tracking, lock, delayed children and aftermath. Retargeting replaces only that cast's reservation; another active cast from the same owner still counts. Pause freezes timers, owner cancellation clears its leases, and safe checkpoint restoration clears transient reservations because in-flight attacks are deliberately not saved.
- Ordinary and boss rejection clears warning/release state, spends half active cooldown and gives at least one second recovery. Actors can resume movement/basic attacks. Locked geometry is not secretly moved at damage time. A final post-motion-freeze check fails closed if the exact path no longer fits.

## Scoped verification

Official Godot4.6.3, managed isolated profiles:

-116 pure geometry/reservation checks across all seven rooms and all18 ordinary/six boss command forms
-15 real Room/ordinary/BO05 checks: rejection, half cooldown, visible-state cancellation, resumed casting, locked geometry, pause and owner cleanup
-836 existing executable B05 combat checks
-22 existing production M14 sunleaf checks

All passed with zero failures and no script errors after the final change. A concurrent boss-art check initially caught a duplicate local variable while the integration was being edited; that parse defect was fixed before these final runs and no failed result is counted as a pass.

## Remaining limits

The conservative ring/possible-endpoint envelopes can reject a legal-looking cast and need natural-play tuning. The tests establish admission and state behavior, not full encounter pacing, boss difficulty, rendered warning readability, seven-room progression, or user acceptance. All art and runtime chapter release gates remain unchanged.
