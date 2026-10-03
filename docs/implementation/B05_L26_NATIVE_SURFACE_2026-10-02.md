# L26 native floor and fascia recovery

This candidate repair rebuilds the lost overlay code from the documented geometry and retained native artwork. No source image is resized, painted over, or destructively composited.

## Exact inputs and transforms

- Base: byte-restored1536×1024 L26 environment with recovered exact prompt/provenance.
- Floor: recovered1254×1254 native material, lossless WebP re-encoding with decoded RGB equality recorded by the recovery manifest. Runtime repeat period512 source pixels.
- Fascia: newly generated1536×1024 RGBA strip with separate exact prompt and SHA. It is not claimed recovered from the lost instance. Runtime samples its[0,449,1536,160]strip, repeated every512 source pixels and rendered28 source pixels deep.
- Floor repair is limited to[205,680,1130,175] intersected with the frozen room ground; its top32 source pixels feather into the original.
- Fascia binds to the frozen southern polygon edges, entirely outside the walkable boundary, excluding the exact200-world-pixel south entrance. It does not follow a drifting generated edge.
- Alpha below0.01 is discarded; solid strip alpha above0.125 becomes opaque at rendering time. Original PNG bytes remain unchanged. Vertex modulation is captured explicitly, avoiding double texture sampling through fragment COLOR.

`mine_backdrop.configure_layout` loads these layers only when metadata is approved or a dedicated candidate pilot explicitly opts in. Reconfiguration removes a previous candidate. Normal production flags remain closed.

## Verification

Official Godot4.6.3, Mesa llvmpipe OpenGL compatibility, actual1536×1024 SubViewport:13 checks, zero failures, two comparison frames inspected. Floor fills the missing southern walkable area, the native outer strip meets the frozen edge without the earlier blue gap, and the south portal/northern source remain unchanged. A first run encountered missing audio hardware; the repeated graphical run with the Dummy audio driver had no script/error output, only an unsupported V-Sync warning.

The resulting floor strip visibly has different board scale than parts of the mother painting. It remains a candidate for the six native detail tiles and full-camera review, not complete L26 art acceptance. These source textures are1254² and1536×1024 respectively; no native2K claim is made.

A later10-check headless structural test additionally covers real backdrop opt-in/default gating and removal on reconfiguration. Collision geometry,180-wide main route and140-wide safe route remain untouched. Synthetic profiles and the two rendered frames remain under the managed test-output directory, outside Git.
