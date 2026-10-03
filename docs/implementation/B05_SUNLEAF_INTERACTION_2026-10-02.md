# L29 sunleaf shading increment

This gated code increment implements M14's authored fixed-leaf countermeasure. It does not enable B05 departure or approve leaf artwork.

## Explicit implementation supplements

The design fixes two spotlight leaves at the frozen L29 anchors but does not define interaction duration, coverage, or automatic reopening. The implemented rule is a normal F press within the shared 68-world-pixel interaction radius and line of sight, toggling the selected leaf open/closed immediately. It stays in that state until the next valid interaction or saved-state restoration. The nearest authored leaf supplies a caster's sunlight; deterministic authored order breaks an equal-distance tie. Other rooms without fixed leaves retain daylight.

Closing a source immediately interrupts a linked M14 solar cast and cancels only its unresolved sunlight-tagged effects, including the D2 endpoint and D4 second beam. The existing brain applies its half-cooldown interruption rule. Basic attacks stay available, and reopening does not resurrect cancelled commands. Production F lookup, localized hint, input blocking, range and occlusion checks use the actual Room/player path.

## Saving

Production mechanism snapshot version2 adds exact authored `sunleaf_closed` booleans. Version1 snapshots remain readable and initialize both leaves open. Unknown leaves, missing fields or non-booleans are rejected before state changes. JSON numeric version values are validated by integer range rather than typed Array membership, preserving Godot's float-parsed JSON round trip.

## Evidence and remaining work

Official Godot4.6.3, real headless Room/M14 and synthetic isolated profile: 22 checks, zero failures. Covers production F, real telegraph interruption, half cooldown, independently lit eastern source, basic attacks, actual scheduled solar followup cancellation, save migration, invalid restore atomicity, blocked UI/range/line of sight.

Native open/closed art exists in the recovered L29 source package but remains unapproved and is not yet registered by this code increment. Rendered state clarity, collision-free approach, complete L29 encounter flow and natural play acceptance remain required before release.
