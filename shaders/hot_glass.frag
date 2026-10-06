#version 460 core
#include <flutter/runtime_effect.glsl>
precision highp float;
out vec4 fragColor;
uniform vec2 u_size;
uniform float u_press;
uniform vec2 u_pointer;
uniform float u_morph;
uniform float u_radius;
uniform float u_fresnel;
uniform float u_dark;
uniform float u_velocity;
uniform vec2 u_light;
float roundedBoxSdf(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + vec2(radius);
  return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}
void main() {
  vec2 size = max(u_size, vec2(1.0));
  vec2 p = FlutterFragCoord().xy - size * 0.5;
  vec2 halfSize = max(size * 0.5 - vec2(0.5), vec2(0.5));
  float cap = min(halfSize.x, halfSize.y);
  float radius = mix(min(u_radius, cap), cap, u_morph);
  float sdf = roundedBoxSdf(p, halfSize, radius);
  vec2 gradient = vec2(
    roundedBoxSdf(p + vec2(0.5, 0), halfSize, radius) - roundedBoxSdf(p - vec2(0.5, 0), halfSize, radius),
    roundedBoxSdf(p + vec2(0, 0.5), halfSize, radius) - roundedBoxSdf(p - vec2(0, 0.5), halfSize, radius));
  vec2 normal2 = gradient / max(length(gradient), 0.0001);
  vec2 light = u_light / max(length(u_light), 0.0001);
  float bevel = 1.0 - smoothstep(0.0, min(12.0, cap * 0.45), abs(sdf));
  vec3 normal3 = normalize(vec3(normal2 * bevel * 0.8, 1.0));
  float viewDot = clamp(normal3.z, 0.0, 1.0);
  float fresnel = 0.04 + 0.96 * pow(1.0 - viewDot, 5.0);
  float facing = smoothstep(-0.25, 0.9, dot(normal2, light));
  vec3 halfLight = normalize(normalize(vec3(light * 0.75, 1.0)) + vec3(0, 0, 1));
  float specular = pow(max(dot(normal3, halfLight), 0.0), 42.0) * bevel;
  vec2 touchDelta = (FlutterFragCoord().xy / size - u_pointer);
  float touch = exp(-dot(touchDelta, touchDelta) * 24.0) * u_press;
  float highlight = clamp((bevel * facing * (0.10 + fresnel * 1.2) + specular * 0.24 + touch * bevel * 0.035) * u_fresnel * (1.0 + u_velocity * 0.08), 0.0, 0.65);
  float shade = bevel * (1.0 - facing) * mix(0.045, 0.08, u_dark);
  float coverage = 1.0 - smoothstep(-0.5, 0.5, sdf);
  highlight *= coverage;
  shade *= coverage;
  float alpha = clamp(highlight + shade, 0.0, 1.0);
  // Local highlights are an overlay, never a second copy of the backdrop.
  // Output is premultiplied, including completely transparent interior pixels.
  fragColor = vec4(vec3(0.97, 0.985, 1.0) * highlight, alpha);
}
