#version 460 core
#include <flutter/runtime_effect.glsl>

// Legacy ABI: 12 floats, sampler 0. Exactly 11 texture taps.
// Temporary signals: bass = noise (glow radius), mid = noise (scanline/grille
// strength), treble = noise (snow hiss), seed = a fixed grille phase of zero.
// The clock moves the snow and hold bands continuously.
// Motion drives barrel/hold; noise substitutes for burst, with no collapse flash.
// All geometry is normalised; no tile support is claimed with the legacy ABI.
uniform vec2 uSize;
uniform float uNoise;
uniform float uLight;
uniform float uMotion;
uniform float uTime;
uniform vec2 uMotionDir;
uniform vec2 uUvScale;
uniform vec2 uUvOffset;
// Extended contract: bass 12, mid 13, treble 14, seed 15.
uniform float uBass;
uniform float uMid;
uniform float uTreble;
uniform float uSeed;
// Capture micro-fingerprint 16..19; zero disables it.
uniform vec4 uFingerprint;
// Contextual mood 20..23 and sign 24..27: declared for the shared ABI, unused.
uniform vec4 uMood;
uniform vec4 uSign;
uniform sampler2D uImage;
out vec4 fragColor;

const float TAU = 6.28318530718;
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 imageAt(vec2 p) {
  return texture(uImage, clamp(p * uUvScale + uUvOffset, 0.0, 1.0)).rgb;
}
vec2 widthUnits(vec2 p) { return p * vec2(1.0, uSize.x / uSize.y); }
vec2 boundOffset(vec2 p) { return p * min(1.0, 0.044 / max(length(p), 0.000001)); }

void main() {
  vec2 p = FlutterFragCoord().xy / uSize;
  float n = clamp(uNoise, 0.0, 1.0);
  float m = clamp(uMotion, 0.0, 1.0);
  float dark = max(0.0, 1.0 - 2.0 * uLight);
  float bright = max(0.0, 2.0 * uLight - 1.0);
  vec2 d = (p - 0.5) / vec2(1.0, uSize.x / uSize.y);
  float r2 = min(dot(d, d), 4.0);
  // Mild inward curvature, smoothly bounded even on extreme aspect ratios.
  vec2 barrel = boundOffset(-d * (0.06 * r2 + 0.04 * r2 * r2) * m);
  float hold = exp(-pow((p.y - (0.5 + 0.28 * sin(uTime * 0.7))) / 0.07, 2.0));
  vec2 warp = boundOffset(barrel + vec2(0.008 * m * hold * sin(uTime * 2.1), 0.0));
  vec2 q = p + widthUnits(warp);
  vec3 transported = imageAt(q);
  vec3 color = transported;
  vec2 trail = vec2(uMotionDir.x, -uMotionDir.y) * m;
  // Phosphor persistence: two green-biased afterimages, no previous-frame store.
  color = color * 0.60
      + imageAt(p + widthUnits(boundOffset(warp - trail * 0.014))) * 0.24
      + imageAt(p + widthUnits(boundOffset(warp - trail * 0.030))) * 0.16;
  float reference = luma(color);
  float radius = 0.002 + 0.007 * n;
  vec3 glow = vec3(0.0);
  for (int i = 0; i < 8; i++) {
    float a = float(i) * TAU / 8.0;
    vec2 offset = vec2(cos(a), sin(a)) * radius;
    glow += imageAt(p + widthUnits(offset)) * 0.125;
  }
  float lines = 0.5 + 0.5 * cos(p.y * 240.0 * TAU);
  vec3 grille = 0.5 + 0.5 * cos(vec3(0.0, 2.0944, 4.1888) + p.x * 180.0 * TAU);
  color *= 1.0 - n * (0.12 * lines + 0.12 * (1.0 - grille));
  float snowCentre = 0.5 + 0.32 * sin(uTime * 1.3);
  float band = 1.0 - smoothstep(0.0, 0.01, abs(p.y - snowCentre) - (0.01 + 0.06 * n));
  float snow = 0.5 + 0.5 * sin(p.x * 357.0 + p.y * 291.0 + uTime * 5.0);
  color *= 1.0 - 0.26 * n * band * snow;
  color += glow * vec3(0.035, 0.075, 0.043) * n;
  // Bright tube = softer whites; dark tube = green shadow contrast.
  color = mix(color, max(vec3(0.0), (color - 0.045) * vec3(0.80, 1.04, 0.88)), dark);
  color = mix(color, color * vec3(0.80, 0.78, 0.68) + vec3(0.10, 0.10, 0.085), bright);
  // Limit electrical glow relative to the local (possibly transported) picture.
  color *= min(1.0, reference * 1.16 / max(luma(color), 0.000001));
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
