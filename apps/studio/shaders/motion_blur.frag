#version 460 core
#include <flutter/runtime_effect.glsl>

// Averages along uStreak (pixels), centred on each pixel.
uniform vec2 uSize;
uniform vec2 uStreak;
uniform sampler2D uImage;

out vec4 fragColor;

const int kTaps = 48;

vec4 at(vec2 position) {
  vec2 uv = position / uSize;
  if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec4(0.0);
  return texture(uImage, uv);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec4 sum = vec4(0.0);
  for (int i = 0; i < kTaps; i++) {
    float t = float(i) / float(kTaps - 1) - 0.5;
    sum += at(p + uStreak * t);
  }
  fragColor = sum / float(kTaps);
}
