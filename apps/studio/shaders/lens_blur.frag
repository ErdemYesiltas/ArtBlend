#version 460 core
#include <flutter/runtime_effect.glsl>

// A lens's out-of-focus blur: a disc of samples (not a Gaussian), bright
// spots weighed up into bokeh by uBright, then contrast around mid grey.
uniform vec2 uSize;
uniform float uRadius;
uniform float uBright;
uniform float uContrast;
uniform sampler2D uImage;

out vec4 fragColor;

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec4 sum = vec4(0.0);
  float total = 0.0;
  for (int i = 0; i < 64; i++) {
    float r = sqrt((float(i) + 0.5) / 64.0) * uRadius;
    float a = float(i) * 2.39996323;
    vec4 c = texture(uImage, (frag + vec2(cos(a), sin(a)) * r) / uSize);
    float luma = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
    float w = 1.0 + uBright * pow(luma, 4.0) * 12.0;
    sum += c * w;
    total += w;
  }
  vec4 c = sum / total;
  c.rgb = clamp((c.rgb - 0.5 * c.a) * uContrast + 0.5 * c.a, 0.0, c.a);
  fragColor = c;
}
