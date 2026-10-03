# B07 M14–M18 action candidates

Completed 2026-10-03: 15 independent character key poses and 5 separate skill-object/effect candidates. The full selected asset list, native hashes, prompts, provenance, alpha≥16/128 bounds, manual foot points, anatomical body heights and sampling limits are in `index.json`. Every selected asset also has its own `provenance.json` and `prompt.txt` beside the PNG.

All five identities still use base attack fallback for these designed active skills. No runtime coverage is claimed. Three key poses are not continuous animation; M14's second hit/feint sequence is not fully represented. No repository, manifest, runtime, room or numerical data was modified; no gameplay tests or pushes were run.

There are 20 selected native PNGs and 5 superseded original candidates, 25 generated PNGs total. Use `index.json` → `selected_assets` for the intended selection, not directory enumeration. M14/M15 execute use `execute_framing_fix`; M14 slash, M16 scan arc and M17 debris use `*_design_fix`. Every correction was attempted only once. All native source-to-deliverable hashes match. Python was used only for measurement/indexing and diagnostic alpha composites, never editing source PNGs.

QA result: all 20 selected assets have zero alpha≥16 and alpha≥128 pixels touching the canvas edges. Light sandstone and dark purple alpha-composite diagnostics were visually inspected; broad RGB-only warm preview halos are absent in proper compositing. Low-alpha edge noise is retained, and many character margins remain below the requested 8%. Framing fixes improve the two worst execute poses but do not fully achieve the 10% repair target.

Remaining design issues: camera is too low/front-facing, especially M18; M17 execute partially occludes the far foot; M15 grip continuity and detached flag staff topology need review; M18 execute's staff points screen-left while keeping the original hand. VFX angle/width is illustrative, never collision geometry. No 2K runtime, production animation, atlas alignment or complete directional pass is claimed.

`diagnostics/` contains QA-only composites and is not a formal game asset directory. Original material and sources are retained for the integrating owner.
