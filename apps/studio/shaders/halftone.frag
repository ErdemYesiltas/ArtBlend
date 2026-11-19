#version 460 core
#include <flutter/runtime_effect.glsl>

// Halftone: full colour (C, M, Y, K dots on turned grids), screen print
// (dots in the layer's own colours) or newspaper (black dots).
uniform vec2 uSize;
uniform float uCell;
uniform float uType;
uniform sampler2D uImage;

out vec4 fragColor;

// Coverage 0–1 of a dot sized for [value] in the grid turned by [angle].
float dot2(vec2 p, float angle, float value) {
  float c = cos(angle), s = sin(angle);
  vec2 q = mat2(c, -s, s, c) * p / uCell;
  vec2 f = fract(q) - 0.5;
  float r = sqrt(clamp(value, 0.0, 1.0)) * 0.7071;
  return 1.0 - smoothstep(r - 0.06, r + 0.06, length(f));
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec4 c = texture(uImage, p / uSize);
  if (c.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 rgb = c.rgb / c.a;
  vec3 outRgb;
  if (uType < 0.25) {
    float k = 1.0 - max(rgb.r, max(rgb.g, rgb.b));
    vec3 cmy = (1.0 - rgb - k) / max(1.0 - k, 1e-4);
    float cc = dot2(p, 0.2618, cmy.r);
    float mm = dot2(p, 1.309, cmy.g);
    float yy = dot2(p, 0.0, cmy.b);
    float kk = dot2(p, 0.7854, k);
    outRgb = (1.0 - vec3(cc, mm, yy)) * (1.0 - kk);
  } else if (uType < 0.75) {
    float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    float d = dot2(p, 0.7854, 1.0 - luma * 0.85);
    outRgb = mix(vec3(1.0), rgb, d);
  } else {
    float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    outRgb = vec3(1.0 - dot2(p, 0.7854, 1.0 - luma));
  }
  fragColor = vec4(outRgb * c.a, c.a);
}
