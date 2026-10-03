# B05 room transition recovery increment

Rebuilt on PR7 `b1e5a480c8598ae5dc685f90bfe41ca0b1bd5ee5`, after the original uncommitted implementation was lost. This is newly reconstructed code, not a claim of byte-for-byte recovery.

## Implemented

- Production root-well ground collision uses the frozen circular foot radius plus the moving actor's radius. Destroyed root remnants retain their footprint. Navigation receives conservative bounding rectangles while physical movement stays circular.
- The production F interaction and localized hint now resolve nearby, visible, unopened watergates. UI input blocking cancels their channel immediately; confirmed player damage already uses the shared interruption seam.
- Watergate state changes rebuild live obstacle geometry from immutable authored rectangles. Only the matching opened vine barrier is filtered out; restoring a closed checkpoint puts it back. Rendering refreshes with the same geometry.
- Reconfiguration is rejected before mutating the host. Repeated checkpoint restoration remains idempotent. Root-target positions and one per-tick network snapshot avoid repeated deep snapshots for activity queries.

## Scoped evidence

Current recovered machine has **official Godot 4.6.3**, not the 4.7.2 version named in older reports. Full asset import completed without script errors. Root-network value baseline: 67 checks, zero failures. New production-room transition test: 157 checks, zero failures, headless, isolated synthetic profile. It covers circle contact, movement blocking, channel interruption, actual collision removal, JSON closed/open restoration, permanent west bypass, and destroyed-well footprint retention. This does not establish rendered appearance, natural play balance, complete chapter traversal, or compatibility with an untested engine version.

New diagnostic logs and synthetic profiles are kept outside the repository in the designated B05 test-output tree. No player save was recovered, invented, or modified.

## Still blocked from release

Production `implemented_chapters` remains 4. B05 still needs boss root rotation, whole-command hazard admission, M14 shading interaction, complete seven-room encounter/reward/save progression, remaining original art, rendered acceptance and user play acceptance. B06 remains a separate code-only worktree.
