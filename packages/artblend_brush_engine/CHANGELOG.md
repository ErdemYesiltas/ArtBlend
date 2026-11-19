## 0.0.10

- Wet mix for stamp brushes (`ab_stamp_wet`, `StampSettings.dilution`,
  `charge`, `pull`): each dab takes up the colour under it by the pull
  (more when diluted) and mixes it into the colour the brush carries; the
  paint runs out over a distance set by the charge; dilution thins it.
  Strokes then build up their own premultiplied paint per pixel (dabs of
  changing colour), under the same opacity cap and grain; dual brushes
  combine on that paint's coverage. Dry brushes paint as before. Engine
  version `libmypaint-1.6.1/artblend-6`.

## 0.0.9

- Dual brushes (`ab_stamp_dual`, `NativeBrushSurface.loadStamp(dual:)`): a
  second tip stamped along the same stroke with its own size (a share of
  the primary dab), spacing, scatter and jitter builds its own coverage,
  combined with the primary tip's by one of twelve modes (multiply,
  darken, lighten, screen, add, subtract, difference, overlay, colour burn,
  colour dodge, linear burn, hard mix) before the opacity cap and grain.
  Loading a stamp brush makes it single again. Engine version
  `libmypaint-1.6.1/artblend-5`.

## 0.0.8

- Smudge (`ab_brush_smudge`, `NativeBrushSurface.setSmudge`): following
  strokes drag paint instead of laying it, with the configured opacity as
  the strength. MyPaint brushes use libmypaint's smudge with full pick-up
  and a long smudge length (the preset's own values come back when
  smudging ends); stamp brushes drag the pixels under each previous dab to
  the next (bilinear, read before writing), shaped by the tip and grain.
  Engine version `libmypaint-1.6.1/artblend-4`.

## 0.0.7

- Symmetry (`ab_symmetry`, `NativeBrushSurface.setSymmetry`): every stroke
  point is also drawn at `center + M (p − center)` for up to eight row-major
  2×2 matrices (mirrors and rotations; tilt turns with them). MyPaint keeps
  one brush per copy so each copy has its own dynamics; stamp copies keep
  their own path but share the stroke's coverage, so the opacity cap holds
  where copies overlap, and start from the same random seed so mirrored
  jitter matches. Engine version `libmypaint-1.6.1/artblend-3`.

## 0.0.6

- Stamp brushes (`ab_stamp_load`, `NativeBrushSurface.loadStamp`,
  `StampImage`, `StampSettings`): a grayscale tip stamped along the stroke
  with spacing, scatter, size/opacity/rotation jitter, follow-stroke
  rotation and pressure-to-size/opacity, into the same tiled surface as
  libmypaint (dirty tiles, reads and loads unchanged). Dabs build coverage
  by flow; the stroke opacity caps it once, so overlaps never exceed it.
  A grain tiled over the canvas textures that coverage (texturized grain),
  so it stays visible however much paint builds up. A MyPaint preset load
  switches back. Engine version `libmypaint-1.6.1/artblend-2`.

## 0.0.5

- `normalizeMypaintPreset` reads the line-based brush files of MyPaint 1.0
  and earlier (versions 1 and 2) into version 3 JSON: both curve syntaxes,
  renamed settings with their scale, obsolete settings dropped,
  anti-aliasing off unless set. Version 3 JSON passes through unchanged.
- Preset loading sanitizes instead of rejecting real-world deviations:
  unknown settings and inputs are skipped, base values are clamped to their
  range, and curve points that are not finite, too large or not strictly
  increasing are dropped (inputs need two). Still guards the upstream
  64-point mapping arrays and enum lookups; only non-JSON, non-version-3 or
  presets with no usable setting are refused.

## 0.0.4

- Link against libm on every non-Windows target. Android's dynamic linker
  refused the library (`cannot locate symbol "logf"`); Apple platforms fold
  libm into libSystem, so only a physical Android run exposed it.

## 0.0.3

- Dirty tile tracking (`takeDirtyTiles`, worker `takeDirtyChunks`): only the
  64×64 tiles dabs wrote since the last query, cleared on read; loads never
  mark tiles.
- Rectangle IO: `loadRgbaRect`, `readRgbaRect` (straight or premultiplied
  straight from the RGBA16 tiles) on the surface and the worker.

## 0.0.2

- `configure` scales the preset's `opaque` base value instead of replacing
  `opaque_multiply`, so pressure-to-opacity curves of presets keep working.
- `BrushWorker.readRgbaPremultiplied` for engine image upload without a UI
  isolate conversion pass.

## 0.0.1

- Vendored libmypaint 1.6.1 and json-c 0.19 with native build hooks.
- Sparse tile surface, validated version 3 presets, pressure/tilt/eraser input.
- Persistent worker isolate, explicit resource lifetime and RGBA transport.
- Recorded numeric precision and bounded input patches.
