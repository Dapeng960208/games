# M16 native-mouth projectile display

The renderer supplies the three newly measured mouth anchors in room coordinates. Each fan shot starts its visible glyph/trail at its corresponding mouth, then blends its display offset to zero over0.14seconds. Collision origin/position, locked direction/path, travel range, damage and warning geometry are unchanged.

The live M16/projectile check passed16 assertions: three mouths/shots, unchanged physical origins and280-world-pixel range, exact initial visible anchors, half-offset at70ms and coincidence with the physical projectile by140ms. The ordinary-art integration worker inspected the new real release frame and confirmed three mouth-aligned shots. This does not add missing vertical/native-angle artwork; the authored right-facing/mirrored source view remains explicit.
