#version 460 core
#include <flutter/runtime_effect.glsl>

// Legacy ABI: 12 floats, sampler 0. Exactly 3 texture taps.
// Temporary signals: mid = noise (palette mix), treble = noise (sensor hiss),
// seed = fixed contour phase + continuous time drift. No bass signal is needed.
// Noise replaces burst only as contour energy; no white-hot flash is generated.
// Palette strength fades to zero at neutral to honour the current clean contract.
// Width-based sensor latency, normalised contours; legacy ABI is not tile aware.
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

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 imageAt(vec2 p) {
  return texture(uImage, clamp(p * uUvScale + uUvOffset, 0.0, 1.0)).rgb;
}
vec3 heat(float v) {
  vec3 c = mix(vec3(0.02, 0.05, 0.18), vec3(0.10, 0.35, 0.60), smoothstep(0.0, 0.25, v));
  c = mix(c, vec3(0.80, 0.70, 0.30), smoothstep(0.25, 0.50, v));
  c = mix(c, vec3(0.95, 0.35, 0.10), smoothstep(0.50, 0.75, v));
  return mix(c, vec3(1.0), smoothstep(0.75, 1.0, v));
}

void main() {
  vec2 p = FlutterFragCoord().xy / uSize;
  float n = clamp(uNoise, 0.0, 1.0);
  float m = clamp(uMotion, 0.0, 1.0);
  float light = clamp(uLight, 0.0, 1.0);
  float mood = abs(2.0 * light - 1.0);
  vec2 trail = vec2(uMotionDir.x, -uMotionDir.y)
      * vec2(1.0, uSize.x / uSize.y) * 0.030 * m;
  vec3 original = imageAt(p);
  vec3 color = original * (1.0 - 0.52 * m)
      + imageAt(p - trail * 0.5) * 0.28 * m
      + imageAt(p - trail) * 0.24 * m;
  float y = luma(color);
  // Blend a luminance-preserving heat map: contour topology follows the image,
  // unlike the screen-space grille and the radial geometry of the other looks.
  vec3 palette = heat(clamp(y + 0.25 * (light - 0.5), 0.0, 1.0));
  palette *= y / max(luma(palette), 0.000001);
  color = mix(color, palette, min(0.34 * n + 0.62 * mood, 0.80));
  float contour = 0.5 + 0.5 * cos(y * 24.0 * 6.2831853 + uTime * 0.63);
  float ridge = smoothstep(0.80 - 0.18 * n, 0.98, contour);
  float hiss = 0.5 + 0.5 * sin(p.x * 317.0 + p.y * 263.0 + uTime * 3.1);
  color *= 1.0 - n * (0.18 * ridge + 0.045 * hiss);
  // Dark readings separate isotherms; bright readings soften their contrast.
  float dark = max(0.0, 1.0 - 2.0 * light);
  float bright = max(0.0, 2.0 * light - 1.0);
  color = mix(color, color * (0.76 + 0.20 * y), dark);
  color = mix(color, color * 0.70 + vec3(0.10), bright);
  color *= min(1.0, y * 1.16 / max(luma(color), 0.000001));
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
