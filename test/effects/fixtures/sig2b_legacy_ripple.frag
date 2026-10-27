#version 460 core
#include <flutter/runtime_effect.glsl>

// Legacy ABI: 12 floats, sampler 0. Exactly 4 texture taps.
// Temporary signals: bass = noise (front phase), mid = noise (extra rings),
// treble = noise (fine wave strength), seed = fixed off-centre origin. Noise replaces
// burst with continuously travelling packets; no discrete trigger or time reset.
// Motion stretches the wave along the direction and adds directional refraction.
// Normalised, width-based geometry; legacy cover mapping, not tile aware.
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
vec2 widthUnits(vec2 p) { return p * vec2(1.0, uSize.x / uSize.y); }
vec2 boundOffset(vec2 p) { return p * min(1.0, 0.048 / max(length(p), 0.000001)); }

void main() {
  vec2 p = FlutterFragCoord().xy / uSize;
  float n = clamp(uNoise, 0.0, 1.0);
  float m = clamp(uMotion, 0.0, 1.0);
  float dark = max(0.0, 1.0 - 2.0 * uLight);
  float bright = max(0.0, 2.0 * uLight - 1.0);
  vec2 direction = vec2(uMotionDir.x, -uMotionDir.y);
  vec2 d = (p - vec2(0.46, 0.53)) / vec2(1.0, uSize.x / uSize.y);
  vec2 ellipse = d - direction * dot(d, direction) * 0.22 * m;
  float r = length(ellipse);
  vec2 radial = ellipse / max(r, 0.000001);
  // Do not multiply time by a live control: tiny level changes would jump the
  // front after a long session. A bounded phase offset stays responsive.
  float front = 0.30 + 0.23 * sin(uTime * 0.9 + 0.4 * n);
  float wave = 0.0;
  float rings = 0.0;
  for (int i = 0; i < 3; i++) {
    float delta = r - front - float(i) * 0.14;
    float envelope = exp(-pow(delta / 0.020, 2.0));
    float strength = i == 0 ? 1.0 : n;
    wave += strength * envelope * sin(delta * 150.0);
    rings += strength * envelope;
  }
  vec2 displacement = boundOffset(radial * wave * 0.030 * n);
  vec3 original = imageAt(p);
  vec3 refracted = imageAt(p + widthUnits(displacement));
  // Keep the subject even where a front crosses a high-contrast edge.
  vec3 color = mix(original, refracted, 0.30 * n);
  vec2 trail = direction * 0.030 * m;
  vec3 latency = imageAt(p - widthUnits(trail));
  vec3 nearLatency = imageAt(p - widthUnits(trail * 0.5));
  color = color * (1.0 - 0.50 * m) + nearLatency * 0.28 * m + latency * 0.22 * m;
  // Silver crest in the dark; charcoal trough in the light. Multiplicative
  // modulation preserves local texture rather than painting solid rings.
  float crest = min(rings, 1.0) * n;
  color *= 1.0 + crest * (0.08 - 0.24 * uLight);
  color *= 1.0 - 0.08 * n * (0.5 + 0.5 * sin(r * 90.0 - uTime * 1.7));
  vec3 cold = color * vec3(0.77, 0.91, 1.03);
  vec3 warm = color * vec3(0.89, 0.82, 0.69) + vec3(0.055, 0.045, 0.025);
  color = mix(color, cold, dark);
  color = mix(color, warm, bright);
  float reference = luma(original * (1.0 - 0.50 * m) + nearLatency * 0.28 * m + latency * 0.22 * m);
  color *= min(1.0, reference * 1.16 / max(luma(color), 0.000001));
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
