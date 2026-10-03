# B06 ordinary combat candidate

## Verified checkpoint scope

This remains an isolated candidate, not a production release or a strength result. The authoritative inputs are `06_TIDAL_CORAL_CITY.md`, `NEXT_EIGHT_CLASS_GEAR_INDEX.md`, shared `enemy_warning_timing.gd`, and the frozen `b06_enemy_numbers.gd`. No HP/attack/defense tuning is included. The user's latest Boss target is 60–90 seconds for all three classes in the specified D4 G2 standard-build test, with no ending-HP threshold (HP remains diagnostic), superseding the older 35–50 second interval and the intermediate minimum-only rule; this implementation suite does not measure that target.

`b06_enemy_skills.gd` builds ordinary profiles and commands. `b06_enemy_brain.gd` owns tracking, immutable lock, release-start cooldowns and interruption half-cooldowns. `b06_enemy_runtime.gd` uses the real shared collision/health receiver and room-owned tide. Commands retain their resolved numerical source and get the existing warning scaling only once. Delayed damaging stages get their own warning and retain authored minimum inter-stage separation. The same command geometry draws and hits.

Implemented ordinary species: all M01–M18. M08 now has an actual 120-world-pixel capsule wall,7-second lifetime,20% owner maximumHP, flank navigation and breakable center. The room owns wall admission away from the180-wide dry routes, gates, exits and other actors. D2 reduction requires actual projectile delivery context, and D4 destruction exposes its owner for2seconds. The candidate route reads these per-species coverage flags rather than overwriting them.

Support excludes Bosses and anchors. M05 shields use the actual guard component; M13 cannot reduce cooldown below 0.1 seconds. Mines/nets/banners are attackable, finite, count against the existing spawn capacity and create no economic rewards. Mines are capped at two; safe disarm produces no explosion. M15's volley can confirm at most two hits per target. Tide movement uses authored patch directions; M03 reacts to actual tide-shield absorption, and M18 extends each tide guard once rather than refreshing it every frame. Draining invalidates its banner and opens its D4 exposure. Owner cancellation and room reset remove finite effects; summon attempts survive Boss phase cleanup. D4 ordinary dangerous lock points reserve at least0.8seconds separation across the room; Bosses are explicitly excluded. Every locked cast, including repeated basics during an active cooldown, gets its own serial, preventing accidental receipt suppression.

## Explicit candidate geometry/details

The chapter specifies some distances but not every width, interval, duration or visual thickness. The following are implementation choices, not additional recovered user requirements, and require visual/strength review:

- M01 thrust width36; M04 swim width32; M07 fan angle1.8radians and echo width28; M09 charge width52 and collision splash width35/range120.
- M02 foam slow20%; its D4 bounce is95worldpixels farther along the frozen shot direction.
- M05 shield-break slow has radius80. M06 mine health is10% owner maximum where the chapter supplies no mine-health fraction; mine fuse remains authored2seconds.
- M11's side landing is locked first, then its180range lance aims at the original locked target from that landing. A blocked landing cancels the lance instead of teleporting it to an unmarked place. D2's forward waterline is harmless visual terrain, because no damage/status was authored. D4's8% step shield lasts1.5seconds.
- M14 leap landing radius60, side spikes radius30 offset85. The visible trace remains at least1second; wet D4 tracking has20% reduction without hiding its warning.
- M15 projectiles have280range/280speed; central D2 shot is30% slower and radius12, versus radius7. Closed shell lasts2seconds and the recovery preserves at least1.5seconds without shell reduction.
- M16 net remains3seconds and moves a total40 along its authored tide direction at D2+. The center health is authored10% ownerHP; D4 final contraction is a separate0.4a packet.
- M17 primary ring is radius80–160; secondary narrow reverse ring is110–140 with at least1.2seconds separation. M18 D2 narrow waves occur every2seconds while its6second flag remains alive.
- BO06 command builders contain explicit candidate ray length520, lateral offsets±100, claw angle120degrees, and return-ring radii160–300/inner140. Boss brain and safe-room integration are owned by the separate BO06 implementation. These distances do not change authored coefficients or numerical profiles.

## Evidence and remaining limits

Godot4.6.3 managed directed suite `test_b06_enemy_skills.tscn`: **874 checks, zero failures**. Latest run: `20261002T165041428464Z-d7b4a895`. This includes real MineEnemy factory/brain dispatch and runtime damage callbacks for implemented attackers across D0–D4; actual shield, slow, haste, shell, mine disarm, net/root, tide bindings, drain/banner invalidation, pause and retry checks. Lock/CD tests use the real brain. Some directed fixtures position actors or deplete a mechanism directly; these are not natural combat samples and are excluded from strength claims.

The suite does not establish normal-room clear balance, legal-build progression, manual play, rendered telegraph readability, all-class real weapon damage against every breakable, or full midcombat file save/resume. The runtime and ordinary brain expose closed JSON capture/validate/restore APIs. A second suite verifies21checks, including new-instance rebinding of active charges, fuse jobs, breakable anchors, support state, finite summons and hit receipts; resumed damage/status sequences match. Unbound actors, unsupported Objects, forged damage and invalid durations are rejected atomically. Full midcombat file integration remains separate: the room must restore actors, transforms,health/status, Boss brain, single tide, player projectiles and deployments, or fail closed. Preserve the release gate until integrated traversal, rendered and strength testing completes.
