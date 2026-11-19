#version 460 core
#include <flutter/runtime_effect.glsl>

// Bloom's bright pass: what is lighter than the threshold, brightened.
uniform vec2 uSize;
uniform float uThreshold;
uniform float uBurn;
uniform sampler2D uImage;

out vec4 fragColor;

void main() {
  vec4 c = texture(uImage, FlutterFragCoord().xy / uSize);
  if (c.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 rgb = c.rgb / c.a;
  float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
  float k = smoothstep(uThreshold, min(uThreshold + 0.25, 1.0001), luma);
  vec3 glow = rgb * k * (1.0 + uBurn * 2.0);
  fragColor = vec4(glow * c.a, c.a * k);
}
