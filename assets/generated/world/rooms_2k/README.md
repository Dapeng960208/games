# Native-detail room texture packs

Each room folder contains six **newly generated native-detail repaints** of exact overlapping source regions, not an enlarged copy of the original painting. Originals remain in `assets/generated/world/rooms/` and retain all geometry/collision metadata. The renderer keeps those originals as fallback and blends only the short region overlaps.

## Provenance and acceptance

`manifest.json` records the original room/source hash, exact source rectangle, actual native size, full built-in `image_gen` prompt, generated PNG hash, shipped lossless WebP hash, and decoded RGB hash for every tile. The source is this project's existing generated painting; no third-party asset pack was introduced. Full original generation PNGs and preparation crops are local verification artifacts, not duplicate shipped assets.

PNG→WebP conversion is **lossless** and decoded RGB bytes must be identical. Neither preparation nor packaging adds synthetic sharpening, upscales pixels, retouches boundaries, or changes source aspect mapping. Preparation crops are only references for generation. Mipmaps are render imports; shipped native detail remains intact.

`approved=false` means candidate only. Production uses a pack only after its room-specific 2560×1440 center/edge/architecture/seam review and geometry-preservation check. Approved manifests include a QA record and evidence hashes. A missing, incomplete, or unapproved pack leaves the original full painting in use.

## Runtime residency

`scripts/world/environment_detail.gd` owns the six textures on the current room node and releases them on room replacement; there is no global detail-texture cache. Original room painting cache is separately bounded to two entries for active/transition use. Lossless disk compression does not imply compressed GPU residency; a typical six-tile pack is approximately 48 MiB RGBA+mips at runtime.

`tools/package_environment_tiles.py` is the preparation/packaging entry point. It never grants approval. Source geometry, room identity, spawns, enemies, rewards and gameplay remain outside this asset pipeline.
