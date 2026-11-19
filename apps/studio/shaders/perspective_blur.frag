#version 460 core
#include <flutter/runtime_effect.glsl>

// Blur growing with the distance from uCentre (pixels): towards it
// (positional), or along uDirection (directional, a unit vector).
uniform vec2 uSize;
uniform vec2 uCentre;
uniform vec2 uDirection;
uniform float uAmount;
uniform float uDirectional;
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
  vec2 streak = uDirectional > 0.5
      ? -uDirection * length(uCentre - p) * uAmount
      : (uCentre - p) * uAmount;
  vec4 sum = vec4(0.0);
  for (int i = 0; i < kTaps; i++) {
    sum += at(p + streak * (float(i) / float(kTaps - 1)));
  }
  fragColor = sum / float(kTaps);
}
