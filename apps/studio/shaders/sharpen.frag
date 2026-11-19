#version 460 core
#include <flutter/runtime_effect.glsl>

// Unsharp mask: the image plus what its blurred copy lacks.
uniform vec2 uSize;
uniform float uAmount;
uniform sampler2D uImage;
uniform sampler2D uBlur;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 c = texture(uImage, uv);
  vec4 b = texture(uBlur, uv);
  vec3 rgb = c.rgb + (c.rgb - b.rgb) * uAmount;
  fragColor = vec4(clamp(rgb, 0.0, c.a), c.a);
}
