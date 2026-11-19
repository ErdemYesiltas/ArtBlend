#version 460 core
#include <flutter/runtime_effect.glsl>

// Glitch: artifact (blocks shifted), wave (rows swayed), signal (bands
// split into colours with scan lines) or diverge (channels drift apart).
uniform vec2 uSize;
uniform float uAmount;
uniform float uBlock;
uniform float uZoom;
uniform float uType;
uniform sampler2D uImage;

out vec4 fragColor;

float hash(vec2 p) {
  p = fract(p * vec2(443.897, 441.423));
  p += dot(p, p.yx + 19.19);
  return fract((p.x + p.y) * p.x);
}

vec4 at(vec2 p) {
  vec2 uv = p / uSize;
  if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec4(0.0);
  return texture(uImage, uv);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float w = max(uSize.x, uSize.y);
  if (uType < 0.25) {
    // Artifact: random blocks pulled sideways.
    vec2 cell = vec2(uBlock * w * 0.15 + 4.0, uBlock * w * 0.05 + 2.0);
    vec2 id = floor(p / cell);
    float r = hash(id);
    float on = step(1.0 - uAmount * 0.6, r);
    vec2 shift = vec2((hash(id + 3.1) - 0.5) * uZoom * w * 0.2, 0.0);
    fragColor = at(p + shift * on);
  } else if (uType < 0.5) {
    // Wave: rows sway, bands at random.
    float band = floor(p.y / (uBlock * w * 0.08 + 2.0));
    float sway = sin(p.y * 0.05 + hash(vec2(band, 1.0)) * 6.28);
    fragColor = at(p + vec2(sway * uAmount * w * 0.03, 0.0));
  } else if (uType < 0.75) {
    // Signal: bands split into red and blue, with scan lines.
    float band = floor(p.y / (uBlock * w * 0.04 + 2.0));
    float on = step(1.0 - uAmount * 0.7, hash(vec2(band, 7.0)));
    float split = (uZoom * 0.02 + 0.004) * w * on;
    vec4 base = at(p);
    vec4 r = at(p + vec2(split, 0.0));
    vec4 b = at(p - vec2(split, 0.0));
    vec4 c = vec4(r.r, base.g, b.b, max(base.a, max(r.a, b.a)));
    float scan = 1.0 - uAmount * 0.25 * step(0.5, fract(p.y * 0.5));
    fragColor = vec4(c.rgb * scan, c.a);
  } else {
    // Diverge: red and blue drift apart.
    vec2 d = vec2(uAmount * w * 0.02, 0.0);
    vec4 r = at(p + d), g = at(p), b = at(p - d);
    fragColor = vec4(r.r, g.g, b.b, max(g.a, max(r.a, b.a)));
  }
}
