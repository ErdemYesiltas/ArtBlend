#pragma once
#include <stdint.h>
#include <stddef.h>
#if defined(_WIN32)
#define AB_API __declspec(dllexport)
#else
#define AB_API __attribute__((visibility("default"))) __attribute__((used))
#endif

typedef struct ABBrushSurface ABBrushSurface;
#define AB_MAX_COPIES 8
AB_API const char *ab_engine_version(void);
AB_API ABBrushSurface *ab_surface_create(int width, int height);
AB_API void ab_surface_destroy(ABBrushSurface *surface);
/* Returns 0 on invalid preset, leaving the current brush intact. Max 1 MiB. */
AB_API int ab_brush_load(ABBrushSurface *surface, const char *json, size_t length);
/* Overrides radius and HSV color; opacity scales the preset's own opaque base
 * value so pressure curves on opaque_multiply keep working. */
AB_API int ab_brush_configure(ABBrushSurface *surface, float diameter,
    float hue, float saturation, float value, float opacity, int eraser);
AB_API void ab_stroke_begin(ABBrushSurface *surface);
/* x/y in canvas pixels; pressure [0,1], tilt axes [-1,1], seconds (0,1]. */
AB_API int ab_stroke_point(ABBrushSurface *surface, float x, float y,
    float pressure, float xtilt, float ytilt, double seconds);
/* RGBA8 straight alpha, row-major. Exact byte count required. */
AB_API int ab_surface_load_rgba(ABBrushSurface *surface, const uint8_t *rgba, size_t length);
AB_API int ab_surface_read_rgba(ABBrushSurface *surface, uint8_t *rgba, size_t length);
AB_API int ab_surface_allocated_tiles(ABBrushSurface *surface);
/* Rectangle variants: x/y/w/h in pixels inside the surface, exact byte count
 * w*h*4. Reads may return premultiplied RGBA8 for direct GPU upload. */
AB_API int ab_surface_load_rgba_rect(ABBrushSurface *surface, int x, int y,
    int width, int height, const uint8_t *rgba, size_t length);
AB_API int ab_surface_read_rgba_rect(ABBrushSurface *surface, int x, int y,
    int width, int height, int premultiplied, uint8_t *rgba, size_t length);
/* Copies one flag per 64x64 tile (row-major, ceil(w/64)*ceil(h/64) bytes) for
 * tiles dabs wrote since the previous call, then clears them. Loads do not
 * mark tiles. Returns the dirty count, or -1 on a wrong buffer size. */
AB_API int ab_surface_take_dirty(ABBrushSurface *surface, uint8_t *tiles, size_t length);
/* Stamp brushes (as in Procreate): a coverage tip (0-255, 255 paints)
 * stamped along the stroke and modulated by a grain texture tiled over the
 * canvas (0-255, may be NULL). params holds AB_STAMP_PARAMS floats: spacing
 * (x diameter), scatter (x diameter), size_jitter, opacity_jitter, rotation
 * (degrees), rotation_jitter (x 180 degrees), follow_stroke (0/1),
 * pressure_size, pressure_opacity, flow, grain_depth, grain_scale. Dabs build
 * coverage up within a stroke by flow; the configured opacity caps the
 * stroke once, so overlapping dabs never exceed it, and the grain textures
 * that coverage (texturized grain), so it shows however much paint builds. Strokes stamp until the
 * next ab_brush_load. Returns 0 on invalid input, keeping the current brush.
 * Tip edges are at most 512, grain edges at most 1024. */
#define AB_STAMP_PARAMS 12
AB_API int ab_stamp_load(ABBrushSurface *surface, const uint8_t *tip,
    int tip_width, int tip_height, const uint8_t *grain, int grain_width,
    int grain_height, const float *params, int count);
/* Dual brush (Procreate's combined brushes): a second tip stamped along
 * the same strokes, building its own coverage, combined with the primary
 * tip's coverage by a blend mode before the opacity cap and grain. params
 * holds AB_DUAL_PARAMS floats: mode (0 multiply, 1 darken, 2 lighten,
 * 3 screen, 4 add, 5 subtract, 6 difference, 7 overlay, 8 colour burn,
 * 9 colour dodge, 10 linear burn, 11 hard mix), size (x the primary dab,
 * 0.05-4), spacing (x its diameter), scatter (x its diameter), size_jitter,
 * rotation_jitter (x 180 degrees), follow_stroke (0/1). A NULL tip turns
 * it off; ab_stamp_load turns it off too. Returns 0 on invalid input. */
/* Wet mix for stamp brushes (Procreate's): pull (0-1) is how much of the
 * colour under each dab the brush takes up and mixes into its own as it
 * goes; charge (0.01-1) how far its paint lasts (1 never runs out);
 * dilution (0-1) thins the paint and makes it take up more. Each dab then
 * lays the colour the brush carries, built up within the stroke under the
 * same opacity cap. ab_stamp_load makes the brush dry again. Returns 0 on
 * invalid input. */
AB_API int ab_stamp_wet(ABBrushSurface *surface, float dilution, float charge,
    float pull);
#define AB_DUAL_PARAMS 7
#define AB_DUAL_MODES 12
AB_API int ab_stamp_dual(ABBrushSurface *surface, const uint8_t *tip,
    int tip_width, int tip_height, const float *params, int count);
/* Symmetry: every stroke point is also drawn at center + M_i (p - center)
 * for each 2x2 row-major matrix M_i (count 1-8, entries in [-1,1]; tilt
 * turns with it). Copies share the stroke: a stamp brush's opacity cap and
 * coverage hold across them. Set between strokes; count 1 with the
 * identity draws one stroke. */
AB_API int ab_symmetry(ABBrushSurface *surface, const float *matrices,
    int count, float cx, float cy);
/* Smudge mode for following strokes (on until turned off): MyPaint brushes
 * pick up and drag the colour under them; stamp brushes drag the pixels
 * under each previous dab to the next, shaped by the tip and grain. The
 * configured opacity is the strength; the eraser setting is ignored. */
AB_API int ab_brush_smudge(ABBrushSurface *surface, int on);
