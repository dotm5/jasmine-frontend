#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

out vec4 fragColor;

// ImageFilter.shader owns the first vec2 and the first sampler.
uniform vec2 u_size;
uniform float u_time;
uniform float u_press;
uniform vec2 u_pointer;
uniform float u_morph;
uniform float u_radius;
uniform float u_refraction;
uniform float u_dispersion;
uniform float u_fresnel;
uniform float u_luma_bias;
uniform float u_dark_mix;
uniform float u_velocity;
uniform vec2 u_light;
uniform float u_flip_y;
uniform sampler2D u_texture;

float roundedBoxSdf(vec2 point, vec2 halfSize, float radius) {
  vec2 distance = abs(point) - halfSize + vec2(radius);
  return length(max(distance, vec2(0.0))) +
      min(max(distance.x, distance.y), 0.0) - radius;
}

vec4 sampleClamped(vec2 uv) {
  return texture(u_texture, clamp(uv, vec2(0.001), vec2(0.999)));
}

void main() {
  vec2 safeSize = max(u_size, vec2(1.0));
  vec2 fragment = FlutterFragCoord().xy;
  vec2 uv = fragment / safeSize;
  vec2 point = fragment - safeSize * 0.5;
  vec2 halfSize = max(safeSize * 0.5 - vec2(1.0), vec2(1.0));
  float capsuleRadius = min(halfSize.x, halfSize.y);
  float radius = mix(min(u_radius, capsuleRadius), capsuleRadius, u_morph);

  float sdf = roundedBoxSdf(point, halfSize, radius);
  const float epsilon = 1.25;
  vec2 gradient = vec2(
    roundedBoxSdf(point + vec2(epsilon, 0.0), halfSize, radius) -
        roundedBoxSdf(point - vec2(epsilon, 0.0), halfSize, radius),
    roundedBoxSdf(point + vec2(0.0, epsilon), halfSize, radius) -
        roundedBoxSdf(point - vec2(0.0, epsilon), halfSize, radius)
  );
  vec2 surfaceNormal = normalize(gradient + vec2(0.0001));
  float edge = 1.0 - smoothstep(0.0, 9.0, abs(sdf));
  float dome = smoothstep(0.0, max(capsuleRadius * 0.72, 1.0), -sdf);

  // Android filter inputs are vertically inverted relative to
  // FlutterFragCoord. Runtime-effect preprocessing does not expose the active
  // renderer macro here, so Flutter passes the texture orientation explicitly.
  vec2 samplingUv = uv;
  vec2 samplingNormal = surfaceNormal;
  if (u_flip_y > 0.5) {
    samplingUv.y = 1.0 - samplingUv.y;
    samplingNormal.y = -samplingNormal.y;
  }

  vec2 pointerPoint = (u_pointer - vec2(0.5)) * safeSize;
  vec2 pointerDelta = point - pointerPoint;
  vec2 normalizedDelta = pointerDelta / max(safeSize, vec2(1.0));
  float touch = exp(-dot(normalizedDelta, normalizedDelta) * 18.0) * u_press;
  vec2 touchNormal = normalize(pointerDelta + vec2(0.0001));
  if (u_flip_y > 0.5) {
    touchNormal.y = -touchNormal.y;
  }
  float motion = clamp(u_velocity, 0.0, 1.0);
  float breathing = 0.92 + 0.08 * sin(u_time * 3.1);

  // Keep the centre optically stable and bend the backdrop mainly at the
  // curved rim. A large full-surface offset reads as a displaced duplicate;
  // edge-local refraction reads as shaped glass.
  float lens = mix(0.10, 0.92, 1.0 - dome) * breathing;
  vec2 refractionOffset =
      (samplingNormal * lens + touchNormal * touch * 0.42) *
      (u_refraction * (1.0 + motion * 0.25)) / safeSize;
  vec2 refractedUv = samplingUv + refractionOffset;

  // Keep the background recognizable: this is optical glass rather than an
  // acrylic blur. Dispersion then separates the three color channels.
  vec2 texel = 1.0 / safeSize;
  vec4 center = sampleClamped(refractedUv) * 0.82;
  center += sampleClamped(refractedUv + vec2(texel.x * 1.2, 0.0)) * 0.045;
  center += sampleClamped(refractedUv - vec2(texel.x * 1.2, 0.0)) * 0.045;
  center += sampleClamped(refractedUv + vec2(0.0, texel.y * 1.2)) * 0.045;
  center += sampleClamped(refractedUv - vec2(0.0, texel.y * 1.2)) * 0.045;

  vec2 chromaOffset = samplingNormal *
      (u_dispersion * (0.06 + edge * 0.86 + motion * 0.12)) / safeSize;
  vec4 redSample = sampleClamped(refractedUv + chromaOffset);
  vec4 blueSample = sampleClamped(refractedUv - chromaOffset);
  vec3 dispersed = vec3(redSample.r, center.g, blueSample.b);
  vec3 glass = mix(center.rgb, dispersed, 0.76);

  // Per-fragment luminance keeps the glass legible over both covers and plain
  // Material surfaces without a CPU readback pass.
  float luminance = dot(glass, vec3(0.2126, 0.7152, 0.0722));
  float brightBackdrop = smoothstep(0.43, 0.68, luminance + u_luma_bias);
  float adaptiveDark = clamp(mix(brightBackdrop, u_dark_mix, 0.34), 0.0, 1.0);
  float contrastRisk = mix(1.0 - brightBackdrop, brightBackdrop, u_dark_mix);
  vec3 adaptiveTint = mix(vec3(0.94, 0.97, 1.0), vec3(0.055, 0.065, 0.09), adaptiveDark);
  glass = mix(
    glass,
    adaptiveTint,
    0.026 + edge * 0.025 + contrastRisk * 0.055
  );
  glass = (glass - vec3(0.5)) * 1.065 + vec3(0.5);

  vec3 normal3 = normalize(vec3(surfaceNormal * mix(1.48, 0.34, dome), 0.42 + dome));
  vec3 viewDirection = vec3(0.0, 0.0, 1.0);
  float viewDot = clamp(dot(normal3, viewDirection), 0.0, 1.0);
  float schlick = 0.04 + (1.0 - 0.04) * pow(1.0 - viewDot, 5.0);
  float fresnelRim = edge * (0.095 + schlick * 1.38) * u_fresnel;

  vec2 lightPosition = clamp(u_light + (u_pointer - vec2(0.5)) * 0.18, vec2(0.0), vec2(1.0));
  vec2 highlightDelta = (uv - lightPosition) * vec2(1.0, 1.8);
  float movingHighlight = exp(-dot(highlightDelta, highlightDelta) * 22.0) *
      (0.34 + u_press * 0.46 + motion * 0.42);
  float directionalHighlight = pow(
    max(dot(normal3, normalize(vec3(-0.48, -0.34, 0.82))), 0.0),
    13.0
  );
  float lightRim = max(dot(surfaceNormal, normalize(vec2(-0.72, -0.68))), 0.0) * edge;
  float shadeRim = max(dot(surfaceNormal, normalize(vec2(0.68, 0.72))), 0.0) * edge;
  vec3 spectralRim = vec3(0.70, 0.87, 1.0) * fresnelRim;
  spectralRim += vec3(1.0, 0.68, 0.91) * fresnelRim * (0.14 + motion * 0.28);
  glass += spectralRim;
  glass += vec3(1.0, 0.99, 0.96) * lightRim * (0.14 + u_press * 0.08);
  glass *= 1.0 - shadeRim * 0.075;
  glass += vec3(1.0, 0.97, 0.9) *
      (movingHighlight + directionalHighlight * 0.24) * (0.38 + edge * 0.62);

  fragColor = vec4(clamp(glass, 0.0, 1.0), center.a);
}
