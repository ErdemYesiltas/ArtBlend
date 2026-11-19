#version 460 core
#include <flutter/runtime_effect.glsl>

// uLut: 256×1, each channel's curve (gamma already applied).
uniform vec2 uSize;
uniform sampler2D uImage;
uniform sampler2D uLut;

out vec4 fragColor;

float lookUp(float v, int channel) {
  vec4 entry = texture(uLut, vec2((v * 255.0 + 0.5) / 256.0, 0.5));
  return channel == 0 ? entry.r : channel == 1 ? entry.g : entry.b;
}

void main() {
  vec4 pixel = texture(uImage, FlutterFragCoord().xy / uSize);
  if (pixel.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 c = clamp(pixel.rgb / pixel.a, 0.0, 1.0);
  c = vec3(lookUp(c.r, 0), lookUp(c.g, 1), lookUp(c.b, 2));
  fragColor = vec4(c * pixel.a, pixel.a);
}
