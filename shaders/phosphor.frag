#version 460 core
#include <flutter/runtime_effect.glsl>
#include "signature_common.glsl"

// D2-SHADERS-B: 28 floats. Neutral mood/sign dispatch to untouched D1 below.
// uMood.x (civil-time warmth, -1..1): white-temperature gain, combined with
// hue clamped to .96..1.04 and gated by noise; snow scale .90..1.10.
// uMood.y (calendar/moon, -1..1): shadow/glow hue weighted by 1-luma(original),
// vectors (-.5,.25,.5), combined gain <=4%; dominant green tube is preserved.
// uMood.z (scene chroma allowance, .65..1): multiplies only the chromatic
// effect-minus-original residual; original chroma and achromatic contrast stay.
// uMood.w (spectral tilt, -1..1): transfers +/-15% of min(pulsedGlow,snowAmount)
// from broad glow (.075*(1+.15*bass)*pulseGain) to snow; post-pulse sum fixed.
// uSign.xy (heading cos/sin delta, <=12 degrees): rotate hold displacement,
// hold/snow band and snow carrier in short-side coordinates; CRT grille stays.
// uSign.z (rhythm pulse, -1..1): glow amount *=1+.04*pulse*noise (.96..1.04);
// glow already multiplies noise; noise zero bypasses pulse EXACTLY.
// uSign.w: reserved, ignored. Context path: 11 unchanged reads, offsets <=.05
// short side, >=45% original retained; tone <=4%, final fingerprint <=1/255.
// With bands/seed zero, colour alone preserves D1 sampling/retention and uses
// one +/-4% RGB gain cap (including chroma), scaled by max(noise,abs(2*light-1)).
// SIG-2B base recipe: 28 floats, sampler 0; exactly 11 taps (3 persistence + 8 glow/original).
// uSize: positive output pixels; p=fragCoord/size, widthUnits=(1,width/height).
// uUvScale.xy/uUvOffset.xy [0,1]: sample UV=p*scale+offset, clamped to [0,1].
// uNoise [0,1]: radius=0.002+0.007*n; scan/grille attenuation=0.12*n each;
// snow attenuation=0.26*n, half-width=0.01+0.06*n; glow=(.035,.075,.043)*n.
// uLight [0,1]: dark=max(0,1-2L), bright=max(0,2L-1); dark mixes in
// max(0,(color-.045)*(.80,1.04,.88)); bright mixes color*(.80,.78,.68)
// +(.10,.10,.085). Luma cap=1.16 times persistence-reference luma.
// uMotion [0,1]: curvature=-d*(.06*r2+.04*r2*r2)*m; hold=.008*m*Gaussian
// (width .07 UV)*sin(2.1*time); legacy warp cap=.044 width units. Persistence
// weights .60/.24/.16, latter taps offset -.014*m*dir and -.030*m*dir.
// uMotionDir: unit/fading vector (length<=1), screen Y inverted; uTime [0,1e6]: fixed
// clock rates 0.7/2.1/1.3/5, never multiplied by a live band or seed.
// uBass [0,1]: glow radius (0.002+0.007*noise)*(1+0.15*bass), <=0.01035
// width units; glow gain *=1+0.15*bass (green addition <=0.08625*noise).
// uMid [0,1]: scan/grille density *=1+0.10*mid; snow half-width
// (0.01+0.06*noise)*(1+0.10*mid), <=0.077 UV (soft edge 0.01).
// uTreble [0,1]: snow spatial frequency, scan and snow strength *=1+0.15*treble;
// snow attenuation <=0.299*noise, scan attenuation <=0.138*noise.
// uSeed [0,1]: zero bypass; independent arithmetic phases in [0,1) offset
// scan/grille by <=one cycle, snow by <=TAU and hold centre by +/-0.02 UV.
// uFingerprint.xyzw (per-shot fractions [0,1]): x/y/z offset independent R/G/B
// arithmetic hashes (G domain +17 X, B +29 Y); w offsets a shared hash. Each
// term contributes +/-0.5/255, combined <=1/255 per channel, all-zero bypass.
// Final microtexture only; it never moves the macro layout at shutter.
// With extended inputs all zero, the legacy eight-tap glow is EXACTLY retained.
// With nonzero bands/seed one glow tap becomes the original, seven share glow;
// every TOTAL sample offset <=5% short side, final original share >=45%.
// All colour/signature disturbance remains under noise/light/motion controls.
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

const float TAU = 6.28318530718;
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 imageAt(vec2 p) {
  return texture(uImage, clamp(p * uUvScale + uUvOffset, 0.0, 1.0)).rgb;
}
vec2 widthUnits(vec2 p) { return p * vec2(1.0, uSize.x / uSize.y); }
vec2 boundOffset(vec2 p) { return p * min(1.0, 0.044 / max(length(p), 0.000001)); }

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
  float dark = max(0.0, 1.0 - 2.0 * uLight);
  float bright = max(0.0, 2.0 * uLight - 1.0);
  vec2 d = (p - 0.5) / vec2(1.0, uSize.x / uSize.y);
  float r2 = min(dot(d, d), 4.0);
  // Mild inward curvature, smoothly bounded even on extreme aspect ratios.
  vec2 barrel = boundOffset(-d * (0.06 * r2 + 0.04 * r2 * r2) * m);
  float holdOffset = uSeed > 0.0 ? (phase.z - 0.5) * 0.04 : 0.0;
  float hold = exp(-pow((p.y - (0.5 + 0.28 * sin(uTime * 0.7) + holdOffset)) / 0.07, 2.0));
  vec2 warp = boundOffset(barrel + vec2(0.008 * m * hold * sin(uTime * 2.1), 0.0));
  vec3 transported = sig2bSample(p, widthUnits(warp), signedRecipe);
  vec3 color = transported;
  vec2 trail = vec2(uMotionDir.x, -uMotionDir.y) * m;
  // Phosphor persistence: two green-biased afterimages, no previous-frame store.
  color = color * 0.60
      + sig2bSample(p, widthUnits(boundOffset(warp - trail * 0.014)), signedRecipe) * 0.24
      + sig2bSample(p, widthUnits(boundOffset(warp - trail * 0.030)), signedRecipe) * 0.16;
  float reference = luma(color);
  float radius = (0.002 + 0.007 * n) * (1.0 + 0.15 * uBass);
  vec3 original = transported;
  vec3 glow = vec3(0.0);
  for (int i = 0; i < 8; i++) {
    float a = signedRecipe ? float(i - 1) * TAU / 7.0 : float(i) * TAU / 8.0;
    vec2 offset = vec2(cos(a), sin(a)) * radius;
    if (signedRecipe && i == 0) offset = vec2(0.0);
    vec3 tap = sig2bSample(p, widthUnits(offset), signedRecipe);
    if (signedRecipe && i == 0) original = tap;
    else glow += tap * (signedRecipe ? 1.0 / 7.0 : 0.125);
  }
  float lines = 0.5 + 0.5 * cos(p.y * 240.0 * TAU * (1.0 + 0.10 * uMid) + phase.x * TAU);
  vec3 grille = 0.5 + 0.5 * cos(vec3(0.0, 2.0944, 4.1888) + p.x * 180.0 * TAU * (1.0 + 0.10 * uMid) + phase.y * TAU);
  color *= 1.0 - n * (0.12 * lines * (1.0 + 0.15 * uTreble) + 0.12 * (1.0 - grille));
  float snowCentre = 0.5 + 0.32 * sin(uTime * 1.3);
  float band = 1.0 - smoothstep(0.0, 0.01, abs(p.y - snowCentre) - ((0.01 + 0.06 * n) * (1.0 + 0.10 * uMid)));
  float snow = 0.5 + 0.5 * sin((p.x * 357.0 + p.y * 291.0) * (1.0 + 0.15 * uTreble) + uTime * 5.0 + phase.z * TAU);
  color *= 1.0 - 0.26 * n * band * snow * (1.0 + 0.15 * uTreble);
  color += glow * vec3(0.035, 0.075, 0.043) * n * (1.0 + 0.15 * uBass);
  // Bright tube = softer whites; dark tube = green shadow contrast.
  color = mix(color, max(vec3(0.0), (color - 0.045) * vec3(0.80, 1.04, 0.88)), dark);
  color = mix(color, color * vec3(0.80, 0.78, 0.68) + vec3(0.10, 0.10, 0.085), bright);
  // Limit electrical glow relative to the local (possibly transported) picture.
  color *= min(1.0, reference * 1.16 / max(luma(color), 0.000001));
  if (signedRecipe) color = signatureRetainOriginal(original, clamp(color, 0.0, 1.0), 1.0);
  color = signatureMicroFingerprint(clamp(color, 0.0, 1.0), p, uFingerprint);
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}

// D2-LEGACY-END: source-locked delivery-1 implementation.

// Colour-only signals keep D1 sampling/retention. Bound the entire correction,
// including chroma allowance, by a shared +/-4% gain on the final D1 RGB.
vec3 sig2dColorOnly(vec3 color, vec3 original) {
  vec3 base = clamp(color, 0.0, 1.0);
  float activity = max(clamp(uNoise, 0.0, 1.0), abs(2.0 * uLight - 1.0));
  vec3 tone = clamp(uMood.x * vec3(1.0, -0.25, -1.0)
      + uMood.y * (1.0 - luma(original)) * vec3(-0.5, 0.25, 0.5), -1.0, 1.0);
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
  float dark = max(0.0, 1.0 - 2.0 * uLight);
  float bright = max(0.0, 2.0 * uLight - 1.0);
  vec2 d = (p - 0.5) / vec2(1.0, uSize.x / uSize.y);
  float r2 = min(dot(d, d), 4.0);
  // Mild inward curvature, smoothly bounded even on extreme aspect ratios.
  vec2 barrel = boundOffset(-d * (0.06 * r2 + 0.04 * r2 * r2) * m);
  float holdOffset = uSeed > 0.0 ? (phase.z - 0.5) * 0.04 : 0.0;
  // Same expression as the frozen delivery-1 body: pulse -> 0 must converge to it
  // on every backend, including its backend-defined pow of a negative base.
  float hold = exp(-pow((p.y - (0.5 + 0.28 * sin(uTime * 0.7) + holdOffset)) / 0.07, 2.0));
  vec2 warp = boundOffset(barrel + vec2(0.008 * m * hold * sin(uTime * 2.1), 0.0));
  vec3 transported = sig2bSample(p, widthUnits(warp), signedRecipe);
  vec3 color = transported;
  vec2 trail = vec2(uMotionDir.x, -uMotionDir.y) * m;
  // Phosphor persistence: two green-biased afterimages, no previous-frame store.
  color = color * 0.60
      + sig2bSample(p, widthUnits(boundOffset(warp - trail * 0.014)), signedRecipe) * 0.24
      + sig2bSample(p, widthUnits(boundOffset(warp - trail * 0.030)), signedRecipe) * 0.16;
  float reference = luma(color);
  float radius = (0.002 + 0.007 * n) * (1.0 + 0.15 * uBass);
  vec3 original = transported;
  vec3 glow = vec3(0.0);
  for (int i = 0; i < 8; i++) {
    float a = signedRecipe ? float(i - 1) * TAU / 7.0 : float(i) * TAU / 8.0;
    vec2 offset = vec2(cos(a), sin(a)) * radius;
    if (signedRecipe && i == 0) offset = vec2(0.0);
    vec3 tap = sig2bSample(p, widthUnits(offset), signedRecipe);
    if (signedRecipe && i == 0) original = tap;
    else glow += tap * (signedRecipe ? 1.0 / 7.0 : 0.125);
  }
  float lines = 0.5 + 0.5 * cos(p.y * 240.0 * TAU * (1.0 + 0.10 * uMid) + phase.x * TAU);
  vec3 grille = 0.5 + 0.5 * cos(vec3(0.0, 2.0944, 4.1888) + p.x * 180.0 * TAU * (1.0 + 0.10 * uMid) + phase.y * TAU);
  color *= 1.0 - n * (0.12 * lines * (1.0 + 0.15 * uTreble) + 0.12 * (1.0 - grille));
  float snowCentre = 0.5 + 0.32 * sin(uTime * 1.3);
  float band = 1.0 - smoothstep(0.0, 0.01, abs(p.y - snowCentre) - ((0.01 + 0.06 * n) * (1.0 + 0.10 * uMid)));
  float snow = 0.5 + 0.5 * sin((p.x * 357.0 + p.y * 291.0) * (1.0 + 0.15 * uTreble) + uTime * 5.0 + phase.z * TAU);
  color *= 1.0 - 0.26 * n * band * snow * (1.0 + 0.15 * uTreble);
  color += glow * vec3(0.035, 0.075, 0.043) * n * (1.0 + 0.15 * uBass)
      * (1.0 + 0.04 * uSign.z * n);
  // Bright tube = softer whites; dark tube = green shadow contrast.
  color = mix(color, max(vec3(0.0), (color - 0.045) * vec3(0.80, 1.04, 0.88)), dark);
  color = mix(color, color * vec3(0.80, 0.78, 0.68) + vec3(0.10, 0.10, 0.085), bright);
  // Limit electrical glow relative to the local (possibly transported) picture.
  color *= min(1.0, reference * 1.16 / max(luma(color), 0.000001));
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

// Only the effect's chromatic residual is scaled. Original RGB is never graded
// toward grey by the allowance; achromatic effect contrast is retained.
vec3 sig2dChroma(vec3 original, vec3 effected) {
  vec3 added = effected - original;
  vec3 grey = vec3(luma(added));
  return original + grey + (added - grey) * uMood.z;
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
  vec2 axis = n > 0.0 ? uSign.xy : vec2(1.0, 0.0);
  vec2 sampleAspect = uSize / max(min(uSize.x, uSize.y), 1.0);
  float grainScale = 1.0 + 0.10 * uMood.x;
  float pulseGain = 1.0 + 0.04 * uSign.z * n;
  vec3 phase = vec3(0.0);
  if (uSeed > 0.0) {
    phase = vec3(signatureHash(vec2(1.0, 7.0), uSeed),
        signatureHash(vec2(11.0, 3.0), uSeed),
        signatureHash(vec2(5.0, 19.0), uSeed));
  }
  float dark = max(0.0, 1.0 - 2.0 * uLight);
  float bright = max(0.0, 2.0 * uLight - 1.0);
  vec2 widthScale = vec2(1.0, uSize.x / uSize.y);
  vec2 shortToUv = min(uSize.x, uSize.y) / uSize;
  vec2 d = (p - 0.5) / widthScale;
  float r2 = min(dot(d, d), 4.0);
  // Mild inward curvature, smoothly bounded even on extreme aspect ratios.
  vec2 barrel = boundOffset(-d * (0.06 * r2 + 0.04 * r2 * r2) * m);
  vec2 shortPosition = signatureAspectPosition(p, uSize);
  vec2 defectPosition = n > 0.0 ? 0.5 + vec2(
      axis.x * shortPosition.x + axis.y * shortPosition.y,
      -axis.y * shortPosition.x + axis.x * shortPosition.y) * shortToUv : p;
  float holdOffset = uSeed > 0.0 ? (phase.z - 0.5) * 0.04 : 0.0;
  float q = (defectPosition.y - (0.5 + 0.28 * sin(uTime * 0.7) + holdOffset)) / 0.07;
  float hold = exp(-(q * q));
  vec2 warp = boundOffset(barrel + sig2dRotate(vec2(0.008 * m * hold * sin(uTime * 2.1), 0.0)));
  vec3 transported = sig2dSample(p, warp * widthScale, sampleAspect);
  vec3 color = transported;
  vec2 trail = vec2(uMotionDir.x, -uMotionDir.y) * m;
  // Phosphor persistence: two green-biased afterimages, no previous-frame store.
  color = color * 0.60
      + sig2dSample(p, boundOffset(warp - trail * 0.014) * widthScale, sampleAspect) * 0.24
      + sig2dSample(p, boundOffset(warp - trail * 0.030) * widthScale, sampleAspect) * 0.16;
  float reference = luma(color);
  float radius = (0.002 + 0.007 * n) * (1.0 + 0.15 * uBass);
  vec3 original = imageAt(p);
  vec3 glow = vec3(0.0);
  // Original first, then the same seven additions in the same order as D1.
  for (int i = 0; i < 7; i++) {
    float a = float(i) * TAU / 7.0;
    vec2 offset = vec2(cos(a), sin(a)) * radius;
    glow += sig2dSample(p, offset * widthScale, sampleAspect) * (1.0 / 7.0);
  }
  float lines = 0.5 + 0.5 * cos(p.y * 240.0 * TAU * (1.0 + 0.10 * uMid) + phase.x * TAU);
  vec3 grille = 0.5 + 0.5 * cos(vec3(0.0, 2.0944, 4.1888) + p.x * 180.0 * TAU * (1.0 + 0.10 * uMid) + phase.y * TAU);
  color *= 1.0 - n * (0.12 * lines * (1.0 + 0.15 * uTreble) + 0.12 * (1.0 - grille));
  float snowCentre = 0.5 + 0.32 * sin(uTime * 1.3);
  float band = 1.0 - smoothstep(0.0, 0.01, abs(defectPosition.y - snowCentre) - ((0.01 + 0.06 * n) * (1.0 + 0.10 * uMid)));
  vec2 snowAxis = sig2dRotate(vec2(357.0, 291.0)
      * shortToUv);
  float snowPhase = dot(shortPosition, snowAxis) / grainScale + 324.0;
  float snow = 0.5 + 0.5 * sin(snowPhase * (1.0 + 0.15 * uTreble) + uTime * 5.0 + phase.z * TAU);
  float glowAmount = 0.075 * (1.0 + 0.15 * uBass) * pulseGain;
  float snowAmount = 0.26 * (1.0 + 0.15 * uTreble);
  float transfer = 0.15 * tilt * min(glowAmount, snowAmount);
  // Transfer between effective post-pulse coefficients: their sum is fixed.
  color *= 1.0 - n * band * snow * (snowAmount + transfer);
  color += glow * vec3(0.035 / 0.075, 1.0, 0.043 / 0.075)
      * n * (glowAmount - transfer);
  // Bright tube = softer whites; dark tube = green shadow contrast.
  color = mix(color, max(vec3(0.0), (color - 0.045) * vec3(0.80, 1.04, 0.88)), dark);
  color = mix(color, color * vec3(0.80, 0.78, 0.68) + vec3(0.10, 0.10, 0.085), bright);
  vec3 tone = clamp(uMood.x * vec3(1.0, -0.25, -1.0)
      + uMood.y * (1.0 - luma(original)) * vec3(-0.5, 0.25, 0.5), -1.0, 1.0);
  color *= vec3(1.0) + 0.04 * n * tone;
  color = sig2dChroma(original, color);
  // Limit electrical glow relative to the local (possibly transported) picture.
  color *= min(1.0, reference * 1.16 / max(luma(color), 0.000001));
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
    // Use the frozen result itself: its historical pow is backend-dependent.
    // This unsigned colour path adds one original tap, without changing D1 taps.
    sig2dLegacy();
    vec2 p = FlutterFragCoord().xy / uSize;
    fragColor = vec4(clamp(sig2dColorOnly(fragColor.rgb, imageAt(p)), 0.0, 1.0), 1.0);
  }
  else if (colorOnly) sig2dPulse();
  else if (uSign.z != 0.0 && uNoise > 0.0) sig2dPulse();
  else sig2dLegacy();
}
