# ArtBlend brush engine

Pinned libmypaint 1.6.1 and json-c 0.19, built from vendored C sources with Flutter/Dart native build hooks. No host-installed brush library is needed.

`NativeBrushSurface` owns a sparse 64×64 RGBA16 tile store. `BrushWorker` owns that surface in a persistent isolate and batches pressure/tilt/timing input off the UI thread. Call `close()` when finished. Pixel transport uses straight-alpha RGBA8; native fixed-point conversion can round low-alpha RGB channels by one byte.

MyPaint version 3 JSON import validates settings, enum names, finite values and the upstream 64-point curve limit before invoking the native parser. Invalid imports leave the old preset intact. Unknown/newer settings are explicitly unsupported. Texture PNG/ABR/brushset import is a separate future adapter.

Run `dart test` and `dart analyze` from this directory. Regenerate bindings with `dart run ffigen --config ffigen.yaml`.

This package is an engine component; interactive editor integration and physical tablet validation remain separate acceptance gates. See THIRD_PARTY.md for versions, provenance and license notices.
