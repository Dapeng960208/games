# Retire the old bronze ember lamp

The user identified the bronze container on the right of a BO05 review frame as obsolete. Pixel inspection matched `assets/ui/relic_ember.png`; its dark hexagonal plinth was drawn by Room's legacy ground-relic renderer. The controlled boss fixture retained legacy mine relic positions after changing its layout to BO05.

The obsolete PNG and import sidecar are removed from both current B05/B06 checkouts. Exact bytes remain recoverable in Git history; no unique untracked source was purged. Shared relic visuals now resolve through the stable class-relic registry; RL02/ember uses the already-present flame icon `assets/generated/ui/state_burn_v1.png`. The old dark plinth is replaced by a minimal pickup guide. Chapter scenes do not draw legacy mine ground relics.

Relic IDs, collection interactions, owned state, ranks, descriptions and combat effects are unchanged. This is a targeted retirement of the requested lamp and its display paths, not removal of the floor or unrelated legacy items.

Focused asset/reference/identity/UI checks:17 checks, zero failures. Historical class-relic behavior:77 checks, zero failures with the explicit legacy ruleset matching the fixture's legacy stat resolver. An initial default-ruleset invocation reported14 numerical expectation failures and is not counted as a pass.
