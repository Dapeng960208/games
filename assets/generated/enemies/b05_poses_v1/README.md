# B05 first-room monster key poses

Deliverable: 9 selected native transparent PNGs for B05-M01 藤鞭树卫, B05-M02 种荚炮手 and B05-M04 露珠护蕊. Each identity has exactly one idle, one telegraph and one execute pose. These are authored action key poses, not a complete animation bank. All accepted files are native 1254 × 1254 RGBA, created with the built-in image generation tool and copied byte-for-byte without resizing, trimming, sharpening or alpha manipulation.

## Registration

`manifest.json` contains exact file sizes and SHA-256 hashes, original generation files, visible alpha bounds, source foot contacts, midpoint ground pivot, anatomy/core/outlet anchors, common per-identity reference height, prompt filenames and rejection history. Source anchors are manually inspected recommendations, not a claim that final runtime pixel acceptance has passed.

Use a fixed pixels-to-world scale per identity based on `reference_body_height_px`. Convert each source position with `(source_position - frame.foot) * scale`; use the same transform and horizontal mirror for the body and its visual outlet. Do not normalize every pose by its canvas bounds or alpha bounding box. Actual source pivots differ because the generator did not preserve the requested normalized contact point. M02's telegraph is visually wider, but all nine source canvases have the same measured resolution. Preserve the intentionally braced/crouched and recoil shape changes.

The existing EnemyVisual motion-bank calculation derives scale from actor bounds and bank body_height. Integration should avoid applying the canvas/reference-height ratio twice; these JSON recommendations are not a drop-in assertion of that legacy bank format. Standalone-frame textures or a losslessly packed atlas can use these source regions and pivots without resampling.

## Action semantics

- B05-M01: source-image screen-right shoulder carries the single long vine in all selected poses. Idle hangs low, telegraph raises the same vine, execute sweeps forward. The arm-swapped first telegraph attempt was rejected
- B05-M02: back-mounted living trumpet pod is part of the body. Telegraph braces and aims it, execute shows fired recoil. Seed projectile, arcing path and landing/split effects stay in runtime VFX
- B05-M04: transparent-looking cyan dewdrop/calyx is the defining anatomy. Telegraph gathers hands around it, execute extends hands into a sustained interruptible healing channel. The waterline and target are runtime VFX; this creature cannot heal bosses
- Recovery reuses idle with existing recovery transforms. Recoil and walking remain existing runtime transforms; no extra authored walk, recoil or recovery frames were supplied

## Direction and acceptance boundary

One canonical right-facing high-angle three-quarter view is supplied. Horizontal mirroring can face left. There are no front/back or eight-direction body poses. Vertical attacks can therefore remain side-on even when the runtime VFX correctly follow their committed target direction. Check both horizontal facing and vertical aim explicitly during integration, particularly the asymmetric M01 arm and M02 muzzle.

All selected visible alpha>=16 silhouettes fit fully inside the canvas. A few untouched generated files have invisible alpha=1 residue on an outer edge. The selected artwork passed source inspection on light/dark backgrounds, including a small fixed-density preview. Actual 2560×1440 production-room scale, pivots, clipping, VFX alignment, occlusion, mechanics and performance remain integration QA; `runtime_quality_gate_passed` is intentionally false.

QA composites are only under `/tmp`: `b05-monster-all-pose-contact.png`, `b05-monster-pivot-registration.png` and the idle-only contact image. They are not game assets. No game code, saves, Git commits or B06 content were changed by this art work.
