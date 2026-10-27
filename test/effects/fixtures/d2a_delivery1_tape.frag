#version 460 core

#include <flutter/runtime_effect.glsl>
// Frozen delivery-1 helper snapshot (avoids relative include traversal).
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


// SIG-2A recipe parameters (all ranges inclusive; source = uniform ABI):
// uBass [0,1], filtered low-band energy: tracking amplitude and spatial
//   width *=1..1.15; sine frequency divides by 1+0.15*uBass. The existing
//   sine and constant exponent 10 are reused; no new transcendental calls.
// uMid [0,1], filtered middle-band energy: band/block density *=1..1.15 (31..35.65 bands) and tracking
//   frequency 22..25.3/short side; duty compensation keeps damage <=20%.
// uTreble [0,1], filtered high-band energy: row density 180..201.6, jitter/chroma split *=1..1.12;
//   fine hiss <=0.004*uNoise*uTreble before retention.
// uSeed [0,1], pending-shot source: independent bounded phase offsets
//   (row/hash clock +97*s, bands +13*s, blocks +7*s, columns +5*s,
//   fine hash +31.7*s, light grain +(31,17)*s); no amplitude added.
//   It never scales uTime.
//   Tracking sine phase +=2*pi*s.
// uFingerprint.xyzw [0,1]^4, capture source: each lane hashes an independent
//   normalized 4096-cell microtexture; w adds shared grain. Applied LAST,
//   x/y/z seed red/green/blue with cell offsets (0,0)/(17,0)/(0,29);
//   each lane and w contributes <=0.5/255, combined <=1/255 per channel.
//   Zero is an exact bypass. It never moves macro
//   features: the shutter can replace the provisional fingerprint seamlessly.
// Existing controls: uNoise [0,1] gates onset n^.75, tears smoothstep(.25,
//   .65,n), damage smoothstep(.60,1,n), wet <=n^.65; all warp/split/grain
//   vanish at n=0. uLight [0,1] grades dark/cold or bright/warm with weights
//   max((.5-L)*2,0)^.65 / max((L-.5)*2,0)^.65 and style constants below.
//   uMotion [0,1] scales/mixes a six-position trail by m^.65; uMotionDir
//   (sensor direction, length<=1, components [-1,1]) multiplies that trail;
//   y is negated for UV. Bands never replace the direction or main controls.
// uTime [0,1e6] seconds: floor(t*GLITCH_RATE), blocks at twice that rate;
//   no band/seed time scaling. uSize (>0 pixels) supplies normalized aspect
//   geometry and block raster reservation. uUvScale/uUvOffset [0,1]^2 are
//   cover mapping only; uImage (camera RGB [0,1], sampler 0) is read clamped.
// Nonzero bands/seed: TOTAL warp+split+trail <=0.05 short side and >=45%
//   untouched original in the final pre-micro mix (including grade/flashes).
// Bloom radius <=0.012 short side; samples remain <=28 (6*4 + 4 bloom).
// All bands/seed zero: exact legacy recipe, exempt from new budget to retain
//   historical pixels. Fingerprint-only changes remain <=1 RGB8 code.
// Live/still use this same recipe and frozen uniforms; no local state.

// Fixed float indices: size 0..1, noise 2, light 3, motion 4, time 5,
// direction 6..7, cover scale 8..9, cover offset 10..11. Image is sampler 0.
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
// Contextual mood 20..23: warmth, hue, chroma allowance, spectral tilt.
uniform vec4 uMood;
// Contextual signature 24..27: orientation axis, rhythmic pulse, reserved.
uniform vec4 uSign;
uniform sampler2D uImage;

out vec4 fragColor;

// Faded analog chroma, broad tracking tears and long exposure ghosts.
const float TRAIL_LENGTH = 0.12;
const float DARK_CONTRAST = 1.22;
const float DARK_GRAIN = 0.055;
const float DARK_VIGNETTE = 0.64;
const float WASH_CONTRAST = 0.66;
const float BRIGHT_SATURATION = 0.68;
const vec2 LEAK_CORNER = vec2(0.0, 1.0);
const vec3 LEAK_COLOR = vec3(0.25, 0.105, 0.025);
const float GLITCH_RATE = 12.0;
const float ROW_COUNT = 180.0;
const float BAND_COUNT = 31.0;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float luma(vec3 c) {
  return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 sampleImage(vec2 uv) {
  // Clamp after cover mapping; never wrap the opposite edge into the picture.
  return texture(uImage, clamp(uv * uUvScale + uUvOffset, 0.0, 1.0)).rgb;
}

vec2 noiseOffset(vec2 offset) {
  // Bound EACH channel's combined displacement in units of screen width.
  // This also bounds diagonal prism dispersion, at any output aspect ratio.
  offset *= min(1.0, 0.049 / max(length(offset), 0.000001));
  return offset * vec2(1.0, uSize.x / uSize.y);
}

vec3 noiseSample(vec2 uv, vec2 shift, vec2 split, float wet) {
  vec3 clean = sampleImage(uv);
  if (wet <= 0.0) return clean;
  vec3 torn = vec3(
      sampleImage(uv + noiseOffset(shift + split)).r,
      sampleImage(uv + noiseOffset(shift)).g,
      sampleImage(uv + noiseOffset(shift - split)).b);
  return mix(clean, torn, wet);
}

vec3 motionSample(vec2 uv, vec2 shift, vec2 split, float wet) {
  vec3 color = noiseSample(uv, shift, split, wet);
  if (uMotion <= 0.0 || length(uMotionDir) <= 0.0) return color;
  // Smooth, one-sided smear plus two distant ghosts; never quantize motion.
  float response = pow(clamp(uMotion, 0.0, 1.0), 0.65);
  // uMotionDir.y is "up" in screen space, but uv.y grows downwards. Negate
  // so that "shake up" smears the picture up, the same way it does on X.
  vec2 trail = vec2(uMotionDir.x, -uMotionDir.y) * vec2(1.0, uSize.x / uSize.y)
      * response * TRAIL_LENGTH;
  vec3 smeared = color * 0.30
      + noiseSample(uv - trail * 0.12, shift, split, wet) * 0.18
      + noiseSample(uv - trail * 0.28, shift, split, wet) * 0.16
      + noiseSample(uv - trail * 0.46, shift, split, wet) * 0.14
      + noiseSample(uv - trail * 0.72, shift, split, wet) * 0.12
      + noiseSample(uv - trail, shift, split, wet) * 0.10;
  return mix(color, smeared, response);
}

vec3 moodGrade(vec3 color, vec2 uv, float tick) {
  float dark = pow(clamp((0.5 - uLight) * 2.0, 0.0, 1.0), 0.65);
  float bright = pow(clamp((uLight - 0.5) * 2.0, 0.0, 1.0), 0.65);
  if (dark > 0.0) {
    // Shadow contrast, crushed toe, and teal-blue midtones.
    vec3 cold = max((color - 0.10) * DARK_CONTRAST, 0.0);
    cold *= vec3(0.60, 0.91, 1.10);
    cold += vec3(0.0, 0.024, 0.055) * (1.0 - clamp(cold, 0.0, 1.0));
    float grain = hash(floor(uv * vec2(640.0, 640.0 * uSize.y / uSize.x))
        + vec2(tick, tick * 0.37)) * 2.0 - 1.0;
    cold += grain * DARK_GRAIN * (0.35 + 0.65 * (1.0 - luma(color)));
    float edge = smoothstep(0.15, 0.70, length(uv - 0.5));
    cold *= 1.0 - DARK_VIGNETTE * edge;
    color = mix(color, cold, dark);
  }
  if (bright > 0.0) {
    // Four broad taps gather only bright neighbours, preserving the subject.
    vec2 radius = vec2(0.012, 0.012 * uSize.x / uSize.y);
    vec3 bloom = max(sampleImage(uv + vec2(radius.x, 0.0)) - 0.62, 0.0)
        + max(sampleImage(uv - vec2(radius.x, 0.0)) - 0.62, 0.0)
        + max(sampleImage(uv + vec2(0.0, radius.y)) - 0.62, 0.0)
        + max(sampleImage(uv - vec2(0.0, radius.y)) - 0.62, 0.0);
    vec3 warm = color * WASH_CONTRAST + vec3(0.14, 0.105, 0.075);
    warm += vec3(0.15, 0.045, -0.075) * smoothstep(0.20, 0.90, luma(color));
    warm += bloom * 0.16 * vec3(1.0, 0.72, 0.38);
    // Corner flare is a mood cue, independent of noise and time.
    float flare = pow(max(0.0, 1.0 - length((uv - LEAK_CORNER)
        * vec2(1.0, 0.85)) / 0.95), 2.0);
    warm += flare * LEAK_COLOR;
    float saturation = BRIGHT_SATURATION;
    warm = mix(vec3(luma(warm)), warm, saturation);
    // Soft shoulder prevents the combined bloom/leak from whitening the frame.
    warm = mix(warm, vec3(0.86) + (warm - 0.86) * 0.28, step(0.86, warm));
    color = mix(color, warm, bright);
  }
  return clamp(color, 0.0, 1.0);
}

vec3 legacyRecipe() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float noise = clamp(uNoise, 0.0, 1.0);
  float onset = pow(noise, 0.75);
  float tearing = smoothstep(0.25, 0.65, noise);
  float corruption = smoothstep(0.60, 1.0, noise);
  // Immediate amplitude response to a shout; only the pattern clock is stepped.
  float tick = floor(uTime * GLITCH_RATE);
  float row = floor(uv.y * ROW_COUNT);
  float jitter = hash(vec2(row, tick)) * 2.0 - 1.0;
  float band = step(0.64, hash(vec2(floor(uv.y * BAND_COUNT), tick + 11.0)));
  float slab = hash(vec2(floor(uv.y * BAND_COUNT), tick + 3.0)) * 2.0 - 1.0;
  // Thin corruption bands cover at most 16% of the continuous frame. Reserve
  // one raster row per band so sampling cannot push coverage above 20%, even
  // in tiny previews. Horizontal gaps can only reduce that area. Refresh twice
  // as often as the tears, without changing the light grain's clock.
  float blockTick = floor(uTime * GLITCH_RATE * 2.0);
  float blockBands = min(BAND_COUNT, max(1.0, floor(uSize.y / 32.0)));
  float blockDuty = min(0.16, max(0.0, 0.20 - blockBands / uSize.y));
  float bandPhase = uv.y * blockBands + hash(vec2(blockTick, 17.0));
  vec2 block = vec2(floor(uv.x * 12.0), floor(bandPhase));
  float broken = (1.0 - step(blockDuty, fract(bandPhase)))
      * step(0.35, hash(block + blockTick));
  float blockShift = (hash(block + vec2(blockTick, 9.0)) * 2.0 - 1.0) * broken;
  vec2 shift;
  vec2 split;
  float tracking = pow(0.5 + 0.5 * sin(uv.y * 22.0 - tick * 0.27), 10.0);
  shift = vec2(jitter * 0.0025 * onset
      + (slab * band * 0.016 + tracking * 0.012) * tearing
      + blockShift * 0.014 * corruption, 0.0);
  split = vec2(0.0065 * onset + 0.006 * tearing + 0.009 * corruption, 0.0);
  // Preserve local image detail even across hard edges: ordinary tears retain
  // >=70% of the original pixel, and heavy bands retain >=28%. Their remaining
  // content is sampled from the image, never replaced by a flat dark dropout.
  float wet = min(pow(noise, 0.65), mix(0.30, 0.72, broken * corruption));
  vec3 color = motionSample(uv, shift, split, wet);
  color = moodGrade(color, uv, tick);
  // One thin row in occasional stepped frames. Multiplication, after grading,
  // guarantees flashes stay <= 18% above that local pixel, even in deep black.
  float flash = step(0.90, hash(vec2(tick, 71.0)))
      * step(0.985, fract(uv.y * 96.0 + hash(vec2(tick, 23.0))));
  color *= 1.0 + 0.18 * corruption * flash;
  return clamp(color, 0.0, 1.0);
}

// Signature-only sampling. All offsets are fractions of the short side.
// Reserve warp + dispersion + the WHOLE trail together using the triangle
// inequality; every tap then fits the shared 5% radius without extra reads.
vec3 stpNoiseSample(vec2 uv, vec2 trail, vec2 shift, vec2 split, float wet,
    vec3 clean) {
  if (wet <= 0.0) return clean;
  vec3 torn = vec3(
      sampleImage(uv + trail + shift + split).r,
      sampleImage(uv + trail + shift).g,
      sampleImage(uv + trail + shift - split).b);
  return mix(clean, torn, wet);
}

vec3 stpTrailSample(vec2 uv, vec2 trail, vec2 shift, vec2 split, float wet) {
  return stpNoiseSample(uv, trail, shift, split, wet, sampleImage(uv + trail));
}

vec3 stpMotionSample(vec2 uv, vec2 shift, vec2 split, float wet,
    out vec3 original) {
  float response = pow(clamp(uMotion, 0.0, 1.0), 0.65);
  vec2 trail = vec2(uMotionDir.x, -uMotionDir.y) * response * TRAIL_LENGTH;
  float total = length(shift) + length(split) + length(trail);
  vec2 shortToUv = min(uSize.x, uSize.y) / uSize;
  // Limit an axis-aligned vector of the conservative combined radius once.
  float budgetScale = signatureLimitOffset(vec2(total, 0.0) * shortToUv,
      uSize).x / max(total * shortToUv.x, 0.000001);
  shift *= shortToUv * budgetScale;
  split *= shortToUv * budgetScale;
  trail *= shortToUv * budgetScale;
  original = sampleImage(uv); // Reused by the final original-preserving mix.
  vec3 color = stpNoiseSample(uv, vec2(0.0), shift, split, wet, original);
  if (uMotion <= 0.0 || length(uMotionDir) <= 0.0) return color;
  vec3 smeared = color * 0.30
      + stpTrailSample(uv, -trail * 0.12, shift, split, wet) * 0.18
      + stpTrailSample(uv, -trail * 0.28, shift, split, wet) * 0.16
      + stpTrailSample(uv, -trail * 0.46, shift, split, wet) * 0.14
      + stpTrailSample(uv, -trail * 0.72, shift, split, wet) * 0.12
      + stpTrailSample(uv, -trail, shift, split, wet) * 0.10;
  return mix(color, smeared, response);
}

vec3 stpMoodGrade(vec3 color, vec2 uv, float tick) {
  float dark = pow(clamp((0.5 - uLight) * 2.0, 0.0, 1.0), 0.65);
  float bright = pow(clamp((uLight - 0.5) * 2.0, 0.0, 1.0), 0.65);
  if (dark > 0.0) {
    // Shadow contrast, crushed toe, and teal-blue midtones.
    vec3 cold = max((color - 0.10) * DARK_CONTRAST, 0.0);
    cold *= vec3(0.60, 0.91, 1.10);
    cold += vec3(0.0, 0.024, 0.055) * (1.0 - clamp(cold, 0.0, 1.0));
    float grain = hash(floor(uv * vec2(640.0, 640.0 * uSize.y / uSize.x))
        + vec2(tick, tick * 0.37) + uSeed * vec2(31.0, 17.0)) * 2.0 - 1.0;
    cold += grain * DARK_GRAIN * (0.35 + 0.65 * (1.0 - luma(color)));
    float edge = smoothstep(0.15, 0.70, length(uv - 0.5));
    cold *= 1.0 - DARK_VIGNETTE * edge;
    color = mix(color, cold, dark);
  }
  if (bright > 0.0) {
    // Four broad taps gather only bright neighbours, preserving the subject.
    vec2 radius = 0.012 * min(uSize.x, uSize.y) / uSize;
    vec3 bloom = max(sampleImage(uv + vec2(radius.x, 0.0)) - 0.62, 0.0)
        + max(sampleImage(uv - vec2(radius.x, 0.0)) - 0.62, 0.0)
        + max(sampleImage(uv + vec2(0.0, radius.y)) - 0.62, 0.0)
        + max(sampleImage(uv - vec2(0.0, radius.y)) - 0.62, 0.0);
    vec3 warm = color * WASH_CONTRAST + vec3(0.14, 0.105, 0.075);
    warm += vec3(0.15, 0.045, -0.075) * smoothstep(0.20, 0.90, luma(color));
    warm += bloom * 0.16 * vec3(1.0, 0.72, 0.38);
    // Corner flare is a mood cue, independent of noise and time.
    float flare = pow(max(0.0, 1.0 - length((uv - LEAK_CORNER)
        * vec2(1.0, 0.85)) / 0.95), 2.0);
    warm += flare * LEAK_COLOR;
    float saturation = BRIGHT_SATURATION;
    warm = mix(vec3(luma(warm)), warm, saturation);
    // Soft shoulder prevents the combined bloom/leak from whitening the frame.
    warm = mix(warm, vec3(0.86) + (warm - 0.86) * 0.28, step(0.86, warm));
    color = mix(color, warm, bright);
  }
  return clamp(color, 0.0, 1.0);
}

vec3 stpSignatureRecipe() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 position = signatureAspectPosition(uv, uSize);
  float noise = clamp(uNoise, 0.0, 1.0);
  float onset = pow(noise, 0.75);
  float tearing = smoothstep(0.25, 0.65, noise);
  float corruption = smoothstep(0.60, 1.0, noise);
  float bass = clamp(uBass, 0.0, 1.0);
  float mid = clamp(uMid, 0.0, 1.0);
  float treble = clamp(uTreble, 0.0, 1.0);
  float seed = clamp(uSeed, 0.0, 1.0);
  float tick = floor(uTime * GLITCH_RATE);
  float patternTick = tick + seed * 97.0;
  float density = 1.0 + 0.15 * mid;
  float detail = 1.0 + 0.12 * treble;
  float y = position.y + 0.5;
  float row = floor(y * ROW_COUNT * detail);
  float jitter = (hash(vec2(row, patternTick)) * 2.0 - 1.0) * detail;
  float bandCell = floor(y * BAND_COUNT * density + seed * 13.0);
  float band = step(0.64, hash(vec2(bandCell, patternTick + 11.0)));
  float slab = hash(vec2(bandCell, patternTick + 3.0)) * 2.0 - 1.0;
  float blockTick = floor(uTime * GLITCH_RATE * 2.0) + seed * 97.0;
  // Raster reservation uses OUTPUT-UV density, not short-side density.
  float blockBands = min(BAND_COUNT * density,
      max(1.0, floor(uSize.y / 32.0)));
  float blockDuty = min(0.16, max(0.0, 0.20 - blockBands / uSize.y));
  float bandPhase = uv.y * blockBands + hash(vec2(blockTick, 17.0)) + seed * 7.0;
  vec2 block = vec2(floor((position.x + 0.5) * 12.0 + seed * 5.0), floor(bandPhase));
  float broken = (1.0 - step(blockDuty, fract(bandPhase)))
      * step(0.35, hash(block + blockTick));
  float blockShift = (hash(block + vec2(blockTick, 9.0)) * 2.0 - 1.0) * broken;
  vec2 shift;
  vec2 split;
  float tracking = pow(0.5 + 0.5 * sin(y * 22.0 * density / (1.0 + 0.15 * bass)
      - tick * 0.27 + seed * 6.2831853), 10.0);
  shift = vec2(jitter * 0.0025 * onset
      + (slab * band * 0.016 + tracking * 0.012 * (1.0 + 0.15 * bass)) * tearing
      + blockShift * 0.014 * corruption, 0.0);
  split = vec2((0.0065 * onset + 0.006 * tearing + 0.009 * corruption) * detail, 0.0);
  float wet = min(pow(noise, 0.65), mix(0.30, 0.72, broken * corruption));
  vec3 original;
  vec3 color = stpMotionSample(uv, shift, split, wet, original);
  float fine = signatureHash(floor((position + 0.5) * 640.0 * detail), seed)
      * 2.0 - 1.0;
  color += fine * 0.004 * noise * treble;
  color = stpMoodGrade(color, uv, tick);
  float flash = step(0.90, hash(vec2(patternTick, 71.0)))
      * step(0.985, fract(uv.y * 96.0 + hash(vec2(patternTick, 23.0))));
  color *= 1.0 + 0.18 * corruption * flash;
  return signatureRetainOriginal(original, clamp(color, 0.0, 1.0), 0.55);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  // Exact legacy arithmetic is retained behind a uniform branch. In particular,
  // fingerprint alone does not switch budgets or perturb the macro layout.
  bool signatureEnabled = uBass != 0.0 || uMid != 0.0 || uTreble != 0.0 || uSeed != 0.0;
  vec3 color;
  if (signatureEnabled) {
    color = stpSignatureRecipe();
  } else {
    color = legacyRecipe();
  }
  fragColor = vec4(signatureMicroFingerprint(color, uv, uFingerprint), 1.0);
}
