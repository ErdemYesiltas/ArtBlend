#version 460 core
#include <flutter/runtime_effect.glsl>

// Hue shift (turns), saturation factor, brightness (-1 black … 1 white).
uniform vec2 uSize;
uniform vec3 uAmount;
uniform sampler2D uImage;

out vec4 fragColor;

vec3 rgbToHsv(vec3 c) {
  vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
  vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
  float d = q.x - min(q.w, q.y);
  float e = 1.0e-10;
  return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsvToRgb(vec3 c) {
  vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
  return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void main() {
  vec4 pixel = texture(uImage, FlutterFragCoord().xy / uSize);
  if (pixel.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 c = pixel.rgb / pixel.a;
  vec3 hsv = rgbToHsv(c);
  hsv.x = fract(hsv.x + uAmount.x);
  c = hsvToRgb(hsv);
  float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
  c = clamp(mix(vec3(luma), c, uAmount.y), 0.0, 1.0);
  c = uAmount.z < 0.0 ? c * (1.0 + uAmount.z) : c + (1.0 - c) * uAmount.z;
  fragColor = vec4(c * pixel.a, pixel.a);
}
