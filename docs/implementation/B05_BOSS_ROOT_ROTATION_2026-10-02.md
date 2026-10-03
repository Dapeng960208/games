# BO05 root rotation increment

Current implementation is gated B05 development; normal departure remains at four chapters.

## Explicit timing supplement

The approved design specifies one active well in P1, two in P2, then three wells switching in sequence with at most two supplying power in P3. It does not specify a rotation period. This implementation uses **six seconds per P3 pair**, preserving a fractional elapsed timer and the scheduled activation mask in the existing checkpoint. This is an implementation supplement for play review, not an invented historical design value.

BO05 now starts with one active well immediately after host configuration. P2 enables the first two authored wells. P3 cycles pairs 1+2 → 2+3 → 3+1. Damaged/destroyed and watergate-closed wells are never healed or reopened by rotation. The schedule may temporarily supply fewer than two living wells; it never silently substitutes a destroyed well.

The first legally settled destruction of an active well notifies the boss exposure counter. Destroying an inactive well does not grant an active-root exposure. Existing four-second vulnerability and ten-second internal cooldown remain owned by the boss brain. Snapshot validation rejects a phase mask that would schedule all three wells.

## Evidence and limits

Official Godot4.6.3, headless real Room and real root-well actor test: 29 checks, zero failures. Covers initial phases, pair order, fractional timing, pause, JSON restore/resume, over-cap restore rejection, active/inactive destruction routing, and no resurrection. A counter probe verifies emitted exposure requests; this test does not claim new full boss combat or visual acceptance.

Remaining release blockers include whole-command hazard admission, M14 shading, full chapter encounter/reward/save traversal, remaining native artwork, rendered cues and user acceptance.
