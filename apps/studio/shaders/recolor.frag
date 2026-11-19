#version 460 core
#include <flutter/runtime_effect.glsl>

// Recolor: pixels near the colour under the crosshair take the new colour,
// keeping how far they were from it (their shading). Nearness is the
// largest premultiplied channel difference, as ColorDrop measures it; in
// flood mode only the connected area (the mask) changes.
uniform vec2 uSize;
uniform vec2 uCentre;
uniform float uThreshold;
uniform float uGlobal;
uniform vec3 uColor;
uniform sampler2D uImage;
uniform sampler2D uMask;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 pixel = texture(uImage, uv);
  vec4 target = texture(uImage, (floor(uCentre) + 0.5) / uSize);
  if (pixel.a <= 0.0 || target.a <= 0.0) {
    fragColor = pixel;
    return;
  }
  vec4 d4 = abs(pixel - target);
  float d = max(max(d4.r, d4.g), max(d4.b, d4.a));
  float limit = max(uThreshold, 0.002);
  float w = 1.0 - smoothstep(limit * 0.7, limit, d);
  if (uGlobal < 0.5) w *= texture(uMask, uv).a;
  if (w <= 0.0) {
    fragColor = pixel;
    return;
  }
  vec3 c = pixel.rgb / pixel.a;
  vec3 from = target.rgb / target.a;
  c = clamp(c + (uColor - from) * w, 0.0, 1.0);
  fragColor = vec4(c * pixel.a, pixel.a);
}
