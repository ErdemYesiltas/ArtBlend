#version 460 core
#include <flutter/runtime_effect.glsl>

// Chromatic aberration: red and blue pulled apart, away from a centre
// (perspective, more with distance past the falloff) or along an angle.
uniform vec2 uSize;
uniform float uAmount;
uniform vec2 uCentre;
uniform vec2 uDirection;
uniform float uFalloff;
uniform float uMode;
uniform sampler2D uImage;

out vec4 fragColor;

vec4 at(vec2 p) {
  vec2 uv = p / uSize;
  if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec4(0.0);
  return texture(uImage, uv);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float w = max(uSize.x, uSize.y);
  vec2 d;
  if (uMode < 0.5) {
    vec2 away = p - uCentre;
    float t = smoothstep(uFalloff * 0.5 * w, w * 0.75, length(away));
    d = normalize(away + 1e-6) * t * uAmount * w * 0.02;
  } else {
    d = uDirection * uAmount * w * 0.015;
  }
  vec4 r = at(p + d), g = at(p), b = at(p - d);
  fragColor = vec4(r.r, g.g, b.b, max(g.a, max(r.a, b.a)));
}
