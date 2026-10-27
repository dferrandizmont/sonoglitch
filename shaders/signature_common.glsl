#ifndef SONOGLITCH_SIGNATURE_COMMON_GLSL
#define SONOGLITCH_SIGNATURE_COMMON_GLSL

// Pure helpers only: uniforms stay explicit in every fragment shader.
// Geometry units are fractions of the short side, independent of resolution.
const float SIGNATURE_MAX_DISPLACEMENT = 0.05;
const float SIGNATURE_MIN_ORIGINAL = 0.45;
const float SIGNATURE_MICRO_AMPLITUDE = 1.0 / 255.0;

vec2 signatureAspectPosition(vec2 uv, vec2 size) {
  return (uv - 0.5) * size / max(min(size.x, size.y), 1.0);
}

// Limit the TOTAL sample offset (warp + split + trail), in UV coordinates.
vec2 signatureLimitOffset(vec2 offsetUv, vec2 size) {
  vec2 aspect = size / max(min(size.x, size.y), 1.0);
  float distanceShortSide = length(offsetUv * aspect);
  return offsetUv * min(1.0, SIGNATURE_MAX_DISPLACEMENT /
      max(distanceShortSide, 0.000001));
}

// Reuse the caller's original tap; no texture reads inside shared helpers.
vec3 signatureRetainOriginal(vec3 original, vec3 effected, float wet) {
  return mix(original, effected, clamp(wet, 0.0, 1.0 - SIGNATURE_MIN_ORIGINAL));
}

// Arithmetic hash, no trigonometry. Each fingerprint lane remains independent.
float signatureHash(vec2 position, float seed) {
  vec3 p = fract(vec3(position.xyx) * vec3(0.1031, 0.1030, 0.0973)
      + seed * 31.7);
  p += dot(p, p.yzx + 33.33);
  return fract((p.x + p.y) * p.z);
}

// Apply LAST, after the original-preserving mix. Neutral fixtures are exact.
// At most one RGB8 code value per channel; not a recoverable watermark.
vec3 signatureMicroFingerprint(vec3 color, vec2 uv, vec4 fingerprint) {
  if (all(equal(fingerprint, vec4(0.0)))) return color;
  vec2 cell = floor(uv * 4096.0);
  float sharedTexture = signatureHash(cell, fingerprint.w) - 0.5;
  vec3 grain = vec3(
      signatureHash(cell, fingerprint.x),
      signatureHash(cell + vec2(17.0, 0.0), fingerprint.y),
      signatureHash(cell + vec2(0.0, 29.0), fingerprint.z)) - 0.5;
  return clamp(color + (grain + sharedTexture) * SIGNATURE_MICRO_AMPLITUDE, 0.0, 1.0);
}

#endif
