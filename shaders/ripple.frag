#version 460 core
#include <flutter/runtime_effect.glsl>
#include "signature_common.glsl"

// D2-SHADERS-B: 28 floats. Neutral mood/sign dispatch to untouched D1 below.
// uMood.x (civil-time warmth, -1..1): crest/trough temperature (1,0,-1),
// combined with hue within .96..1.04, noise-gated; fine radial scale .90..1.10.
// uMood.y (calendar/moon, -1..1): crest-weighted hue (.5,-.5,1); combined
// warmth+hue gain clamped to +/-4%, never a new ring or a replacement control.
// uMood.z (scene chroma allowance, .65..1): scales the chromatic residual added
// by the effect, preserving the original RGB term and achromatic contrast.
// uMood.w (spectral tilt, -1..1): transfers +/-15% of min(broadEnvelope,detail)
// between refraction + pulsed crest and fine attenuation; post-pulse sum fixed.
// broadEnvelope=.030+abs(.08-.24*light)*pulseGain; broad gain stays .85..1.15.
// uSign.xy (heading cos/sin, <=12 degrees): oriented extra ellipticity
// .04*min(abs(sinDelta)/sin(12deg),1), <=4%; never replaces uMotionDir.
// uSign.z (rhythm pulse, -1..1): crest *=1+.04*pulse*noise (.96..1.04),
// already noise-gated; noise zero bypasses pulse EXACTLY. uSign.w ignored.
// Context path: unchanged 4 reads, <=.05 short-side displacement, >=45%
// original retained, combined tone gain <=4%, final fingerprint <=1/255.
// With bands/seed zero, colour alone preserves D1 sampling/retention and uses
// one +/-4% RGB gain cap (including chroma), scaled by max(noise,abs(2*light-1)).
// SIG-2B base recipe: 28 floats, sampler 0; exactly 4 taps (original/refraction/2 trails).
// uSize: positive output pixels; p=fragCoord/size, widthUnits=(1,width/height).
// uUvScale.xy/uUvOffset.xy [0,1]: sample UV=p*scale+offset, clamped to [0,1].
// uNoise [0,1]: refraction=.030*n*radial*wave (legacy cap=.048 width units),
// blend=.30*n; secondary ring weights=n, fine attenuation=.08*n;
// crest gain=min(rings,1)*n*(.08-.24*light), preserving local texture.
// uLight [0,1]: dark/bright weights=max(0,1-2L)/max(0,2L-1); dark mixes
// color*(.77,.91,1.03), bright mixes color*(.89,.82,.69)+(.055,.045,.025).
// Luma cap=1.16 times original/trail-reference luma.
// uMotion [0,1]: ellipse -=dir*dot(d,dir)*.22*m; trail=.030*m*dir;
// trail weights .28*m/.22*m (half/full offset); current weight=1-.50*m.
// uMotionDir: unit/fading vector (length<=1), screen Y inverted; uTime [0,1e6]: front 0.9 and
// detail 1.7 fixed clock rates, never multiplied by a live band or seed.
// uBass [0,1]: front radius excursion 0.23*(1+0.15*bass), <=0.2645 width units;
// crest width 0.020*(1+0.15*bass), <=0.023; phase offset <=0.15 radians.
// uMid [0,1]: secondary ring spacing 0.14*(1+0.15*mid), <=0.161, and secondary
// weights noise*(1+0.15*mid), <=1.15*noise; still exactly three rings.
// uTreble [0,1]: crest oscillation 150*(1+0.15*treble), fine radial frequency
// 90*(1+0.15*treble), fine attenuation 0.08*noise*(1+0.15*treble), <=0.092.
// uSeed [0,1]: zero bypass; independent arithmetic phases in [0,1) offset
// origin by +/-0.03 width units per axis, front <=TAU and detail <=TAU radians.
// uFingerprint.xyzw (per-shot fractions [0,1]): x/y/z offset independent R/G/B
// arithmetic hashes (G domain +17 X, B +29 Y); w offsets a shared hash. Each
// term contributes +/-0.5/255, combined <=1/255 per channel, all-zero bypass.
// Final microtexture only; it never moves the macro layout at shutter.
// Extended-zero inputs retain EXACT legacy pixels. Nonzero bands/seed enable
// total offsets <=5% short side and original share >=45%; no extra noise budget.
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
vec2 widthUnits(vec2 p) { return p * vec2(1.0, uSize.x / uSize.y); }
vec2 boundOffset(vec2 p) { return p * min(1.0, 0.048 / max(length(p), 0.000001)); }

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
  vec2 direction = vec2(uMotionDir.x, -uMotionDir.y);
  vec2 originOffset = uSeed > 0.0 ? widthUnits((phase.xy - 0.5) * 0.06) : vec2(0.0);
  vec2 d = (p - vec2(0.46, 0.53) - originOffset) / vec2(1.0, uSize.x / uSize.y);
  vec2 ellipse = d - direction * dot(d, direction) * 0.22 * m;
  float r = length(ellipse);
  vec2 radial = ellipse / max(r, 0.000001);
  // Do not multiply time by a live control: tiny level changes would jump the
  // front after a long session. A bounded phase offset stays responsive.
  float front = 0.30 + 0.23 * (1.0 + 0.15 * uBass) * sin(uTime * 0.9 + 0.4 * n + 0.15 * uBass + phase.z * 6.2831853);
  float wave = 0.0;
  float rings = 0.0;
  for (int i = 0; i < 3; i++) {
    float delta = r - front - float(i) * 0.14 * (1.0 + 0.15 * uMid);
    float envelope = exp(-pow(delta / (0.020 * (1.0 + 0.15 * uBass)), 2.0));
    float strength = i == 0 ? 1.0 : n * (1.0 + 0.15 * uMid);
    wave += strength * envelope * sin(delta * 150.0 * (1.0 + 0.15 * uTreble));
    rings += strength * envelope;
  }
  vec2 displacement = boundOffset(radial * wave * 0.030 * n);
  vec3 original = imageAt(p);
  vec3 refracted = sig2bSample(p, widthUnits(displacement), signedRecipe);
  // Keep the subject even where a front crosses a high-contrast edge.
  vec3 color = mix(original, refracted, 0.30 * n);
  vec2 trail = direction * 0.030 * m;
  vec3 latency = sig2bSample(p, -widthUnits(trail), signedRecipe);
  vec3 nearLatency = sig2bSample(p, -widthUnits(trail * 0.5), signedRecipe);
  color = color * (1.0 - 0.50 * m) + nearLatency * 0.28 * m + latency * 0.22 * m;
  // Silver crest in the dark; charcoal trough in the light. Multiplicative
  // modulation preserves local texture rather than painting solid rings.
  float crest = min(rings, 1.0) * n;
  color *= 1.0 + crest * (0.08 - 0.24 * uLight);
  color *= 1.0 - 0.08 * n * (1.0 + 0.15 * uTreble) * (0.5 + 0.5 * sin(r * 90.0 * (1.0 + 0.15 * uTreble) - uTime * 1.7 + phase.y * 6.2831853));
  vec3 cold = color * vec3(0.77, 0.91, 1.03);
  vec3 warm = color * vec3(0.89, 0.82, 0.69) + vec3(0.055, 0.045, 0.025);
  color = mix(color, cold, dark);
  color = mix(color, warm, bright);
  float reference = luma(original * (1.0 - 0.50 * m) + nearLatency * 0.28 * m + latency * 0.22 * m);
  color *= min(1.0, reference * 1.16 / max(luma(color), 0.000001));
  if (signedRecipe) color = signatureRetainOriginal(original, clamp(color, 0.0, 1.0), 1.0);
  color = signatureMicroFingerprint(clamp(color, 0.0, 1.0), p, uFingerprint);
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}

// D2-LEGACY-END: source-locked delivery-1 implementation.

// Colour-only signals keep D1 sampling/retention, with one shared gain cap.
vec3 sig2dColorOnly(vec3 color, vec3 original, float rings) {
  vec3 base = clamp(color, 0.0, 1.0);
  float activity = max(clamp(uNoise, 0.0, 1.0), abs(2.0 * uLight - 1.0));
  vec3 tone = clamp(uMood.x * vec3(1.0, 0.0, -1.0)
      + uMood.y * min(rings, 1.0) * vec3(0.5, -0.5, 1.0), -1.0, 1.0);
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
  vec2 direction = vec2(uMotionDir.x, -uMotionDir.y);
  vec2 originOffset = uSeed > 0.0 ? widthUnits((phase.xy - 0.5) * 0.06) : vec2(0.0);
  vec2 d = (p - vec2(0.46, 0.53) - originOffset) / vec2(1.0, uSize.x / uSize.y);
  vec2 ellipse = d - direction * dot(d, direction) * 0.22 * m;
  float r = length(ellipse);
  vec2 radial = ellipse / max(r, 0.000001);
  // Do not multiply time by a live control: tiny level changes would jump the
  // front after a long session. A bounded phase offset stays responsive.
  float front = 0.30 + 0.23 * (1.0 + 0.15 * uBass) * sin(uTime * 0.9 + 0.4 * n + 0.15 * uBass + phase.z * 6.2831853);
  float wave = 0.0;
  float rings = 0.0;
  for (int i = 0; i < 3; i++) {
    float delta = r - front - float(i) * 0.14 * (1.0 + 0.15 * uMid);
    // Same expression as the frozen delivery-1 body (backend-defined pow of a negative base).
    float envelope = exp(-pow(delta / (0.020 * (1.0 + 0.15 * uBass)), 2.0));
    float strength = i == 0 ? 1.0 : n * (1.0 + 0.15 * uMid);
    wave += strength * envelope * sin(delta * 150.0 * (1.0 + 0.15 * uTreble));
    rings += strength * envelope;
  }
  vec2 displacement = boundOffset(radial * wave * 0.030 * n);
  vec3 original = imageAt(p);
  vec3 refracted = sig2bSample(p, widthUnits(displacement), signedRecipe);
  // Keep the subject even where a front crosses a high-contrast edge.
  vec3 color = mix(original, refracted, 0.30 * n);
  vec2 trail = direction * 0.030 * m;
  vec3 latency = sig2bSample(p, -widthUnits(trail), signedRecipe);
  vec3 nearLatency = sig2bSample(p, -widthUnits(trail * 0.5), signedRecipe);
  color = color * (1.0 - 0.50 * m) + nearLatency * 0.28 * m + latency * 0.22 * m;
  // Silver crest in the dark; charcoal trough in the light. Multiplicative
  // modulation preserves local texture rather than painting solid rings.
  float crest = min(rings, 1.0) * n * (1.0 + 0.04 * uSign.z * n);
  color *= 1.0 + crest * (0.08 - 0.24 * uLight);
  color *= 1.0 - 0.08 * n * (1.0 + 0.15 * uTreble) * (0.5 + 0.5 * sin(r * 90.0 * (1.0 + 0.15 * uTreble) - uTime * 1.7 + phase.y * 6.2831853));
  vec3 cold = color * vec3(0.77, 0.91, 1.03);
  vec3 warm = color * vec3(0.89, 0.82, 0.69) + vec3(0.055, 0.045, 0.025);
  color = mix(color, cold, dark);
  color = mix(color, warm, bright);
  float reference = luma(original * (1.0 - 0.50 * m) + nearLatency * 0.28 * m + latency * 0.22 * m);
  color *= min(1.0, reference * 1.16 / max(luma(color), 0.000001));
  if (signedRecipe) color = signatureRetainOriginal(original, clamp(color, 0.0, 1.0), 1.0);
  if (uMood.x != 0.0 || uMood.y != 0.0 || uMood.z < 1.0)
    color = sig2dColorOnly(color, original, rings);
  color = signatureMicroFingerprint(clamp(color, 0.0, 1.0), p, uFingerprint);
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}

// D2 helpers are local: other recipe jobs can add independent shared helpers.
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
  vec2 direction = vec2(uMotionDir.x, -uMotionDir.y);
  vec2 originOffset = uSeed > 0.0 ? ((phase.xy - 0.5) * 0.06) * widthScale : vec2(0.0);
  vec2 d = (p - vec2(0.46, 0.53) - originOffset) / widthScale;
  vec2 ellipse = d - direction * dot(d, direction) * 0.22 * m;
  // Heading adds at most 4% ellipticity; motion direction remains independent.
  float axisAmount = 0.04 * min(abs(axis.y) / 0.20791169, 1.0);
  ellipse -= axis * dot(ellipse, axis) * axisAmount;
  float r = length(ellipse);
  vec2 radial = ellipse / max(r, 0.000001);
  // Do not multiply time by a live control: tiny level changes would jump the
  // front after a long session. A bounded phase offset stays responsive.
  float front = 0.30 + 0.23 * (1.0 + 0.15 * uBass) * sin(uTime * 0.9 + 0.4 * n + 0.15 * uBass + phase.z * 6.2831853);
  float wave = 0.0;
  float rings = 0.0;
  for (int i = 0; i < 3; i++) {
    float delta = r - front - float(i) * 0.14 * (1.0 + 0.15 * uMid);
    float q = delta / (0.020 * (1.0 + 0.15 * uBass));
    float envelope = exp(-(q * q));
    float strength = i == 0 ? 1.0 : n * (1.0 + 0.15 * uMid);
    wave += strength * envelope * sin(delta * 150.0 * (1.0 + 0.15 * uTreble));
    rings += strength * envelope;
  }
  float broadAmount = 0.030;
  // Include the pulsed crest's maximum absolute contrast in the broad budget.
  float crestAmount = abs(0.08 - 0.24 * uLight) * pulseGain;
  float broadEnvelope = broadAmount + crestAmount;
  float detailAmount = 0.08 * (1.0 + 0.15 * uTreble);
  float transfer = 0.15 * tilt * min(broadEnvelope, detailAmount);
  float broadGain = (broadEnvelope - transfer) / broadEnvelope;
  broadAmount *= broadGain;
  detailAmount += transfer;
  vec2 displacement = boundOffset(radial * wave * broadAmount * n);
  vec3 original = imageAt(p);
  vec3 refracted = sig2dSample(p, displacement * widthScale, sampleAspect);
  // Keep the subject even where a front crosses a high-contrast edge.
  vec3 color = mix(original, refracted, 0.30 * n);
  vec2 trail = direction * 0.030 * m;
  vec3 latency = sig2dSample(p, -trail * widthScale, sampleAspect);
  vec3 nearLatency = sig2dSample(p, -(trail * 0.5) * widthScale, sampleAspect);
  color = color * (1.0 - 0.50 * m) + nearLatency * 0.28 * m + latency * 0.22 * m;
  // Silver crest in the dark; charcoal trough in the light. Multiplicative
  // modulation preserves local texture rather than painting solid rings.
  float cappedRings = min(rings, 1.0);
  float crest = cappedRings * n * broadGain * pulseGain;
  color *= 1.0 + crest * (0.08 - 0.24 * uLight);
  color *= 1.0 - detailAmount * n * (0.5 + 0.5 * sin(r / grainScale * 90.0 * (1.0 + 0.15 * uTreble) - uTime * 1.7 + phase.y * 6.2831853));
  vec3 cold = color * vec3(0.77, 0.91, 1.03);
  vec3 warm = color * vec3(0.89, 0.82, 0.69) + vec3(0.055, 0.045, 0.025);
  color = mix(color, cold, dark);
  color = mix(color, warm, bright);
  vec3 tone = clamp(uMood.x * vec3(1.0, 0.0, -1.0)
      + uMood.y * cappedRings * vec3(0.5, -0.5, 1.0), -1.0, 1.0);
  color *= vec3(1.0) + 0.04 * n * tone;
  color = sig2dChroma(original, color);
  float reference = luma(original * (1.0 - 0.50 * m) + nearLatency * 0.28 * m + latency * 0.22 * m);
  color *= min(1.0, reference * 1.16 / max(luma(color), 0.000001));
  color = signatureRetainOriginal(original, clamp(color, 0.0, 1.0), 1.0);
  color = signatureMicroFingerprint(clamp(color, 0.0, 1.0), p, uFingerprint);
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}

// The unsigned colour path reuses frozen D1 pixels, including its retention.
// Only hue needs a ring mask; it cannot change sampling, geometry or contrast.
float sig2dColorRings(vec2 p) {
  if (uMood.y == 0.0) return 0.0;
  float n = clamp(uNoise, 0.0, 1.0);
  float m = clamp(uMotion, 0.0, 1.0);
  vec2 direction = vec2(uMotionDir.x, -uMotionDir.y);
  vec2 d = (p - vec2(0.46, 0.53)) / vec2(1.0, uSize.x / uSize.y);
  float r = length(d - direction * dot(d, direction) * 0.22 * m);
  float front = 0.30 + 0.23 * sin(uTime * 0.9 + 0.4 * n);
  float rings = 0.0;
  for (int i = 0; i < 3; i++) {
    float q = (r - front - float(i) * 0.14) / 0.020;
    rings += (i == 0 ? 1.0 : n) * exp(-(q * q));
  }
  return min(rings, 1.0);
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
    fragColor = vec4(clamp(sig2dColorOnly(fragColor.rgb, imageAt(p),
        sig2dColorRings(p)), 0.0, 1.0), 1.0);
  }
  else if (colorOnly) sig2dPulse();
  else if (uSign.z != 0.0 && uNoise > 0.0) sig2dPulse();
  else sig2dLegacy();
}
