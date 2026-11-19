#version 460 core
#include <flutter/runtime_effect.glsl>

// uLut: 256×1 gradient, dark to light; uAmount mixes it in.
uniform vec2 uSize;
uniform float uAmount;
uniform sampler2D uImage;
uniform sampler2D uLut;

out vec4 fragColor;

void main() {
  vec4 pixel = texture(uImage, FlutterFragCoord().xy / uSize);
  if (pixel.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 c = clamp(pixel.rgb / pixel.a, 0.0, 1.0);
  float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
  vec3 mapped = texture(uLut, vec2((luma * 255.0 + 0.5) / 256.0, 0.5)).rgb;
  fragColor = vec4(mix(c, mapped, uAmount) * pixel.a, pixel.a);
}
