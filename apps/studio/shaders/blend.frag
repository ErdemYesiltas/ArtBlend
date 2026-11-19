#version 460 core
#include <flutter/runtime_effect.glsl>

// A layer (uLayer) composited over its backdrop (uBackdrop), both
// premultiplied, with a blend mode Flutter has no BlendMode for.
uniform vec2 uSize;
uniform float uMode;
uniform float uOpacity;
uniform sampler2D uBackdrop;
uniform sampler2D uLayer;

out vec4 fragColor;

float luma(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }

float burn(float b, float s) {
  if (b >= 1.0) return 1.0;
  if (s <= 0.0) return 0.0;
  return 1.0 - min(1.0, (1.0 - b) / s);
}

float dodge(float b, float s) {
  if (b <= 0.0) return 0.0;
  if (s >= 1.0) return 1.0;
  return min(1.0, b / (1.0 - s));
}

float vivid(float b, float s) {
  return s <= 0.5 ? burn(b, 2.0 * s) : dodge(b, 2.0 * (s - 0.5));
}

vec3 blend(vec3 b, vec3 s, int mode) {
  if (mode == 0) return max(b + s - 1.0, 0.0);                    // linear burn
  if (mode == 1) return luma(s) < luma(b) ? s : b;                // darker color
  if (mode == 2) return luma(s) > luma(b) ? s : b;                // lighter color
  if (mode == 3) return vec3(vivid(b.r, s.r), vivid(b.g, s.g), vivid(b.b, s.b));
  if (mode == 4) return clamp(b + 2.0 * s - 1.0, 0.0, 1.0);       // linear light
  if (mode == 5) {                                                // pin light
    return mix(max(b, 2.0 * s - 1.0), min(b, 2.0 * s), step(s, vec3(0.5)));
  }
  if (mode == 6) return step(1.0, b + s);                         // hard mix
  if (mode == 7) return max(b - s, 0.0);                          // subtract
  // divide
  return vec3(
    s.r <= 0.0 ? 1.0 : min(1.0, b.r / s.r),
    s.g <= 0.0 ? 1.0 : min(1.0, b.g / s.g),
    s.b <= 0.0 ? 1.0 : min(1.0, b.b / s.b));
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 back = texture(uBackdrop, uv);
  vec4 src = texture(uLayer, uv) * uOpacity;
  if (src.a <= 0.0) {
    fragColor = back;
    return;
  }
  vec3 cb = back.a > 0.0 ? back.rgb / back.a : vec3(0.0);
  vec3 cs = src.rgb / src.a;
  vec3 mixed = blend(cb, cs, int(uMode + 0.5));
  // W3C compositing: source-over with the blended colour where both are.
  vec3 rgb = src.rgb * (1.0 - back.a) + back.rgb * (1.0 - src.a) +
      src.a * back.a * mixed;
  fragColor = vec4(rgb, src.a + back.a * (1.0 - src.a));
}
