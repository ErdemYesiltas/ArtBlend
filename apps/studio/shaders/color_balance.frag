#version 460 core
#include <flutter/runtime_effect.glsl>

// Cyan–red, magenta–green, yellow–blue shifts (-1…1) per tonal range.
uniform vec2 uSize;
uniform vec3 uShadows;
uniform vec3 uMidtones;
uniform vec3 uHighlights;
uniform sampler2D uImage;

out vec4 fragColor;

void main() {
  vec4 pixel = texture(uImage, FlutterFragCoord().xy / uSize);
  if (pixel.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 c = pixel.rgb / pixel.a;
  float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
  float shadows = 1.0 - smoothstep(0.0, 0.5, luma);
  float highlights = smoothstep(0.5, 1.0, luma);
  float midtones = 1.0 - shadows - highlights;
  c += (uShadows * shadows + uMidtones * midtones + uHighlights * highlights) * 0.5;
  fragColor = vec4(clamp(c, 0.0, 1.0) * pixel.a, pixel.a);
}
