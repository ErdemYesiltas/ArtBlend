#version 460 core
#include <flutter/runtime_effect.glsl>

// Fractal noise laid over the layer's colours: clouds, billows (|n|) or
// ridges (1 - |n|); turbulence bends the noise by itself.
uniform vec2 uSize;
uniform float uAmount;
uniform float uScale;
uniform float uOctaves;
uniform float uTurbulence;
uniform float uType;
// Where the noise field starts (pixels), so it can drift over time.
uniform vec2 uOffset;
uniform sampler2D uImage;

out vec4 fragColor;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float valueNoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash(i), b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

float fbm(vec2 p) {
  float sum = 0.0, amplitude = 0.5, total = 0.0;
  for (int i = 0; i < 8; i++) {
    float on = step(float(i) + 0.5, uOctaves);
    float n = valueNoise(p);
    if (uType > 0.25 && uType < 0.75) n = abs(n) * 2.0 - 1.0;
    if (uType >= 0.75) n = 1.0 - abs(n) * 2.0;
    sum += n * amplitude * on;
    total += amplitude * on;
    amplitude *= 0.5;
    p = p * 2.03 + vec2(17.1, 9.7);
  }
  return sum / max(total, 1e-4);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec4 c = texture(uImage, frag / uSize);
  if (c.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec2 p = (frag + uOffset) / uScale;
  p += uTurbulence * 3.0 * vec2(fbm(p + 5.2), fbm(p + 1.3));
  float n = fbm(p);
  vec3 rgb = c.rgb / c.a + n * uAmount;
  fragColor = vec4(clamp(rgb, 0.0, 1.0) * c.a, c.a);
}
