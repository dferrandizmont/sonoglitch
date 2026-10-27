#version 460 core
#include <flutter/runtime_effect.glsl>
#include "signature_common.glsl"

// D2-SHADERS-B: 28 floats. Neutral mood/sign dispatch to untouched D1 below.
// uMood.x (civil-time warmth, -1..1): palette temperature (1,0,-1), combined
// gain with hue clamped to .96..1.04; hiss scale .90..1.10.
// uMood.y (calendar/moon, -1..1): palette hue (.5,-.5,1), same combined 4%
// gain cap; palette argument +=.010*hue*noise, contour phase +=.04*hue*noise
// radians. Isotherms still depend on luminance, never the heading axis.
// uMood.z (scene chroma allowance, .65..1): multiplies false-colour mix
// min(.34*noise*(1+.10*mid)+.62*abs(2*light-1),.80); original is not desaturated.
// uMood.w (spectral tilt, -1..1): transfer +/-15% of min(pulsedContour,hiss)
// from contour (.18*pulseGain) to hiss; the post-pulse sum stays fixed.
// uSign.xy (heading cos/sin, <=12 degrees): rotates only the hiss carrier in
// normalized short-side coordinates; no rotation of isotherms or latency.
// uSign.z (rhythm pulse, -1..1): contour *=1+.04*pulse*noise (.96..1.04),
// already noise-gated; noise zero bypasses pulse EXACTLY. uSign.w ignored.
// Context path: unchanged 3 reads, <=.05 short-side displacement, >=45%
// original retained; combined palette gain <=4%, final fingerprint <=1/255.
// With bands/seed zero, colour alone preserves D1 sampling/retention and uses
// one +/-4% RGB gain cap (including chroma), scaled by max(noise,abs(2*light-1)).
// SIG-2B base recipe: 28 floats, sampler 0; exactly 3 taps (original + 2 latency taps).
// uSize: positive output pixels; p=fragCoord/size, widthUnits=(1,width/height).
// uUvScale.xy/uUvOffset.xy [0,1]: sample UV=p*scale+offset, clamped to [0,1].
// uNoise [0,1]: palette weight=min(.34*n+.62*abs(2L-1),.80), ridge lower
// threshold=.80-.18*n; contour/hiss attenuation=.18*n/.045*n.
// uLight [0,1]: palette input adds .25*(L-.5); dark/bright weights
// max(0,1-2L)/max(0,2L-1) mix color*(.76+.20*luma) / color*.70+.10;
// palette is luminance-normalised; final luma cap=1.16*latency-reference luma.
// uMotion [0,1]: latency=.030*m*dir, half/full weights .28*m/.24*m,
// original weight=1-.52*m; uMotionDir is unit/fading (length<=1), Y inverted.
// uTime [0,1e6]: contour 0.63 and hiss 3.1 fixed rates; no live time scaling.
// uBass [0,1]: contour frequency 24*(1-0.15*bass), >=20.4 cycles/luma;
// ridge lower threshold -=0.03*bass (wider/softer transition); no spatial warp.
// uMid [0,1]: contour frequency *=1+0.15*mid, <=27.6 cycles/luma;
// noise palette term 0.34*noise *=1+0.10*mid, <=0.374; total mix capped at 0.80.
// uTreble [0,1]: hiss spatial frequency and intensity *=1+0.15*treble;
// attenuation <=0.05175*noise (multiplicative, preserves scene luminance).
// uSeed [0,1]: zero bypass; independent arithmetic phases in [0,1) offset
// contour/hiss <=TAU radians and palette argument by +/-0.015*noise; palette
// is luminance-normalised, no uniform tint substitutes for spatial diversity.
// uFingerprint.xyzw (per-shot fractions [0,1]): x/y/z offset independent R/G/B
// arithmetic hashes (G domain +17 X, B +29 Y); w offsets a shared hash. Each
// term contributes +/-0.5/255, combined <=1/255 per channel, all-zero bypass.
// Final microtexture only; it never moves the macro layout at shutter.
// Extended-zero inputs retain EXACT legacy pixels. Otherwise total sample
// offsets <=5% short side, final original share >=45%; no extra warp or reads.
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

vec3 sig2bSample(vec2 p, vec2 offsetUv, bool signedRecipe) {
  return imageAt(p + (signedRecipe
      ? signatureLimitOffset(offsetUv, uSize) : offsetUv));
}

void sig2dLegacy() {
  vec2 p = FlutterFragCoord().xy / uSize;
  float n = clamp(uNoise, 0.0, 1.0);
  float m = clamp(uMotion, 0.0, 1.0);
  // A fingerprint must never switch the macro recipe or its budget path.
  bool signedRecipe = uBass > 0.0 || uMid > 0.0 || uTreble > 0.0 || uSeed > 0.0;
  vec3 phase = vec3(0.0);
  if (uSeed > 0.0) {
    phase = vec3(signatureHash(vec2(1.0, 7.0), uSeed),
        signatureHash(vec2(11.0, 3.0), uSeed),
        signatureHash(vec2(5.0, 19.0), uSeed));
  }
  float light = clamp(uLight, 0.0, 1.0);
  float mood = abs(2.0 * light - 1.0);
  vec2 trail = vec2(uMotionDir.x, -uMotionDir.y)
      * vec2(1.0, uSize.x / uSize.y) * 0.030 * m;
  vec3 original = imageAt(p);
  vec3 color = original * (1.0 - 0.52 * m)
      + sig2bSample(p, -trail * 0.5, signedRecipe) * 0.28 * m
      + sig2bSample(p, -trail, signedRecipe) * 0.24 * m;
  float y = luma(color);
  // Blend a luminance-preserving heat map: contour topology follows the image,
  // unlike the screen-space grille and the radial geometry of the other looks.
  float paletteOffset = uSeed > 0.0 ? (phase.z - 0.5) * 0.030 * n : 0.0;
  vec3 palette = heat(clamp(y + 0.25 * (light - 0.5) + paletteOffset, 0.0, 1.0));
  palette *= y / max(luma(palette), 0.000001);
  color = mix(color, palette, min(0.34 * n * (1.0 + 0.10 * uMid) + 0.62 * mood, 0.80));
  float contour = 0.5 + 0.5 * cos(y * 24.0 * 6.2831853 * (1.0 - 0.15 * uBass) * (1.0 + 0.15 * uMid) + uTime * 0.63 + phase.x * 6.2831853);
  float ridge = smoothstep(0.80 - 0.18 * n - 0.03 * uBass, 0.98, contour);
  float hiss = 0.5 + 0.5 * sin((p.x * 317.0 + p.y * 263.0) * (1.0 + 0.15 * uTreble) + uTime * 3.1 + phase.y * 6.2831853);
  color *= 1.0 - n * (0.18 * ridge + 0.045 * hiss * (1.0 + 0.15 * uTreble));
  // Dark readings separate isotherms; bright readings soften their contrast.
  float dark = max(0.0, 1.0 - 2.0 * light);
  float bright = max(0.0, 2.0 * light - 1.0);
  color = mix(color, color * (0.76 + 0.20 * y), dark);
  color = mix(color, color * 0.70 + vec3(0.10), bright);
  color *= min(1.0, y * 1.16 / max(luma(color), 0.000001));
  if (signedRecipe) color = signatureRetainOriginal(original, clamp(color, 0.0, 1.0), 1.0);
  color = signatureMicroFingerprint(clamp(color, 0.0, 1.0), p, uFingerprint);
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}

// D2-LEGACY-END: source-locked delivery-1 implementation.

// Colour-only signals keep the D1 heat map and retention, with one gain cap.
vec3 sig2dColorOnly(vec3 color, vec3 original) {
  vec3 base = clamp(color, 0.0, 1.0);
  float activity = max(clamp(uNoise, 0.0, 1.0), abs(2.0 * uLight - 1.0));
  vec3 tone = clamp(uMood.x * vec3(1.0, 0.0, -1.0)
      + uMood.y * vec3(0.5, -0.5, 1.0), -1.0, 1.0);
  vec3 graded = base * (vec3(1.0) + 0.04 * activity * tone);
  vec3 added = graded - original;
  vec3 grey = vec3(luma(added));
  graded = original + grey + (added - grey) * uMood.z;
  return clamp(graded, base * (1.0 - 0.04 * activity),
      base * (1.0 + 0.04 * activity));
}

// Pulse and colour-only modulation keep the selected D1 sampling/retention.
void sig2dPulse() {
  vec2 p = FlutterFragCoord().xy / uSize;
  float n = clamp(uNoise, 0.0, 1.0);
  float m = clamp(uMotion, 0.0, 1.0);
  // A fingerprint must never switch the macro recipe or its budget path.
  bool signedRecipe = uBass > 0.0 || uMid > 0.0 || uTreble > 0.0 || uSeed > 0.0;
  vec3 phase = vec3(0.0);
  if (uSeed > 0.0) {
    phase = vec3(signatureHash(vec2(1.0, 7.0), uSeed),
        signatureHash(vec2(11.0, 3.0), uSeed),
        signatureHash(vec2(5.0, 19.0), uSeed));
  }
  float light = clamp(uLight, 0.0, 1.0);
  float mood = abs(2.0 * light - 1.0);
  vec2 trail = vec2(uMotionDir.x, -uMotionDir.y)
      * vec2(1.0, uSize.x / uSize.y) * 0.030 * m;
  vec3 original = imageAt(p);
  vec3 color = original * (1.0 - 0.52 * m)
      + sig2bSample(p, -trail * 0.5, signedRecipe) * 0.28 * m
      + sig2bSample(p, -trail, signedRecipe) * 0.24 * m;
  float y = luma(color);
  // Blend a luminance-preserving heat map: contour topology follows the image,
  // unlike the screen-space grille and the radial geometry of the other looks.
  float paletteOffset = uSeed > 0.0 ? (phase.z - 0.5) * 0.030 * n : 0.0;
  vec3 palette = heat(clamp(y + 0.25 * (light - 0.5) + paletteOffset, 0.0, 1.0));
  palette *= y / max(luma(palette), 0.000001);
  color = mix(color, palette, min(0.34 * n * (1.0 + 0.10 * uMid) + 0.62 * mood, 0.80));
  float contour = 0.5 + 0.5 * cos(y * 24.0 * 6.2831853 * (1.0 - 0.15 * uBass) * (1.0 + 0.15 * uMid) + uTime * 0.63 + phase.x * 6.2831853);
  float ridge = smoothstep(0.80 - 0.18 * n - 0.03 * uBass, 0.98, contour);
  float hiss = 0.5 + 0.5 * sin((p.x * 317.0 + p.y * 263.0) * (1.0 + 0.15 * uTreble) + uTime * 3.1 + phase.y * 6.2831853);
  color *= 1.0 - n * (0.18 * ridge * (1.0 + 0.04 * uSign.z * n) + 0.045 * hiss * (1.0 + 0.15 * uTreble));
  // Dark readings separate isotherms; bright readings soften their contrast.
  float dark = max(0.0, 1.0 - 2.0 * light);
  float bright = max(0.0, 2.0 * light - 1.0);
  color = mix(color, color * (0.76 + 0.20 * y), dark);
  color = mix(color, color * 0.70 + vec3(0.10), bright);
  color *= min(1.0, y * 1.16 / max(luma(color), 0.000001));
  if (signedRecipe) color = signatureRetainOriginal(original, clamp(color, 0.0, 1.0), 1.0);
  if (uMood.x != 0.0 || uMood.y != 0.0 || uMood.z < 1.0)
    color = sig2dColorOnly(color, original);
  color = signatureMicroFingerprint(clamp(color, 0.0, 1.0), p, uFingerprint);
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}

// D2 helpers are local: other recipe jobs can add independent shared helpers.
vec2 sig2dRotate(vec2 p) {
  if (uNoise <= 0.0) return p;
  return vec2(uSign.x * p.x - uSign.y * p.y,
      uSign.y * p.x + uSign.x * p.y);
}


// Reuse the short-side conversion across contextual taps; keep every clamp.
vec3 sig2dSample(vec2 p, vec2 offsetUv, vec2 aspect) {
  float distanceShortSide = length(offsetUv * aspect);
  vec2 limited = offsetUv * min(1.0, SIGNATURE_MAX_DISPLACEMENT /
      max(distanceShortSide, 0.000001));
  return imageAt(p + limited);
}

void sig2dContext() {
  vec2 p = FlutterFragCoord().xy / uSize;
  float n = clamp(uNoise, 0.0, 1.0);
  float m = clamp(uMotion, 0.0, 1.0);
  float tilt = n > 0.0 ? uMood.w : 0.0;
  vec2 sampleAspect = uSize / max(min(uSize.x, uSize.y), 1.0);
  float grainScale = 1.0 + 0.10 * uMood.x;
  float pulseGain = 1.0 + 0.04 * uSign.z * n;
  vec3 phase = vec3(0.0);
  if (uSeed > 0.0) {
    phase = vec3(signatureHash(vec2(1.0, 7.0), uSeed),
        signatureHash(vec2(11.0, 3.0), uSeed),
        signatureHash(vec2(5.0, 19.0), uSeed));
  }
  float light = clamp(uLight, 0.0, 1.0);
  float mood = abs(2.0 * light - 1.0);
  vec2 trail = vec2(uMotionDir.x, -uMotionDir.y)
      * vec2(1.0, uSize.x / uSize.y) * 0.030 * m;
  vec3 original = imageAt(p);
  vec3 color = original * (1.0 - 0.52 * m)
      + sig2dSample(p, -trail * 0.5, sampleAspect) * 0.28 * m
      + sig2dSample(p, -trail, sampleAspect) * 0.24 * m;
  float y = luma(color);
  // Blend a luminance-preserving heat map: contour topology follows the image,
  // unlike the screen-space grille and the radial geometry of the other looks.
  float paletteOffset = uSeed > 0.0 ? (phase.z - 0.5) * 0.030 * n : 0.0;
  paletteOffset += 0.010 * uMood.y * n;
  vec3 palette = heat(clamp(y + 0.25 * (light - 0.5) + paletteOffset, 0.0, 1.0));
  palette *= y / max(luma(palette), 0.000001);
  vec3 tone = clamp(uMood.x * vec3(1.0, 0.0, -1.0)
      + uMood.y * vec3(0.5, -0.5, 1.0), -1.0, 1.0);
  palette *= vec3(1.0) + 0.04 * tone;
  color = mix(color, palette, min(0.34 * n * (1.0 + 0.10 * uMid) + 0.62 * mood, 0.80) * uMood.z);
  float contour = 0.5 + 0.5 * cos(y * 24.0 * 6.2831853 * (1.0 - 0.15 * uBass) * (1.0 + 0.15 * uMid) + uTime * 0.63 + 0.04 * uMood.y * n + phase.x * 6.2831853);
  float ridge = smoothstep(0.80 - 0.18 * n - 0.03 * uBass, 0.98, contour);
  vec2 hissAxis = sig2dRotate(vec2(317.0, 263.0)
      * min(uSize.x, uSize.y) / uSize);
  float hissPhase = dot(signatureAspectPosition(p, uSize), hissAxis)
      / grainScale + 290.0;
  float hiss = 0.5 + 0.5 * sin(hissPhase * (1.0 + 0.15 * uTreble) + uTime * 3.1 + phase.y * 6.2831853);
  float contourAmount = 0.18 * pulseGain;
  float hissAmount = 0.045 * (1.0 + 0.15 * uTreble);
  float transfer = 0.15 * tilt * min(contourAmount, hissAmount);
  // Transfer between effective post-pulse coefficients: their sum is fixed.
  color *= 1.0 - n * ((contourAmount - transfer) * ridge
      + (hissAmount + transfer) * hiss);
  // Dark readings separate isotherms; bright readings soften their contrast.
  float dark = max(0.0, 1.0 - 2.0 * light);
  float bright = max(0.0, 2.0 * light - 1.0);
  color = mix(color, color * (0.76 + 0.20 * y), dark);
  color = mix(color, color * 0.70 + vec3(0.10), bright);
  color *= min(1.0, y * 1.16 / max(luma(color), 0.000001));
  color = signatureRetainOriginal(original, clamp(color, 0.0, 1.0), 1.0);
  color = signatureMicroFingerprint(clamp(color, 0.0, 1.0), p, uFingerprint);
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}

void main() {
  // Pulse never selects a recipe; tilt/heading are exact bypasses at zero noise.
  // Fingerprint alone keeps D1; with active colour it uses the signed budget.
  bool signedRecipe = uBass > 0.0 || uMid > 0.0 || uTreble > 0.0 || uSeed > 0.0
      || any(notEqual(uFingerprint, vec4(0.0)));
  bool colorOnly = uMood.x != 0.0 || uMood.y != 0.0 || uMood.z < 1.0;
  bool contextual = (signedRecipe && colorOnly)
      || (uNoise > 0.0 && (uMood.w != 0.0
          || any(notEqual(uSign.xy, vec2(1.0, 0.0)))));
  if (contextual) sig2dContext();
  else if (colorOnly && (uSign.z == 0.0 || uNoise <= 0.0)) {
    // One extra original tap; the frozen D1 sampling/retention stays exact.
    sig2dLegacy();
    vec2 p = FlutterFragCoord().xy / uSize;
    fragColor = vec4(clamp(sig2dColorOnly(fragColor.rgb, imageAt(p)), 0.0, 1.0), 1.0);
  }
  else if (colorOnly) sig2dPulse();
  else if (uSign.z != 0.0 && uNoise > 0.0) sig2dPulse();
  else sig2dLegacy();
}
