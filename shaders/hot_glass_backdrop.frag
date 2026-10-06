#version 460 core
#include <flutter/runtime_effect.glsl>
precision highp float;
out vec4 fragColor;
uniform vec2 u_size;
uniform float u_refraction;
uniform float u_dispersion;
uniform float u_press;
uniform vec2 u_pointer;
uniform float u_pixel_ratio;
uniform float u_velocity;
uniform sampler2D u_texture;
vec4 sampleAt(vec2 uv) { return texture(u_texture, clamp(uv, vec2(0.0), vec2(1.0))); }
void main() {
  vec2 size = max(u_size, vec2(1.0));
  vec2 texel = 1.0 / size;
  vec2 uv = FlutterFragCoord().xy / size;
  vec2 shift = (u_pointer - vec2(0.5)) * u_refraction * u_press * 0.16 * u_pixel_ratio / size;
  uv += shift;
  vec2 blur = texel * u_pixel_ratio * (1.1 + u_velocity * 0.35);
  vec4 color = sampleAt(uv) * 0.60;
  color += sampleAt(uv + vec2(blur.x, 0)) * 0.10;
  color += sampleAt(uv - vec2(blur.x, 0)) * 0.10;
  color += sampleAt(uv + vec2(0, blur.y)) * 0.10;
  color += sampleAt(uv - vec2(0, blur.y)) * 0.10;
  vec2 chroma = texel * u_pixel_ratio * u_dispersion * u_press * 0.04;
  vec4 red = sampleAt(uv + chroma);
  vec4 blue = sampleAt(uv - chroma);
  vec3 dispersed = vec3(red.r, color.g, blue.b);
  // All samples are premultiplied; prevent dispersion from exceeding alpha.
  fragColor = vec4(clamp(mix(color.rgb, dispersed, 0.25), vec3(0), vec3(color.a)), color.a);
}
