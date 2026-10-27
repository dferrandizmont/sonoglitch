#version 460 core

#include <flutter/runtime_effect.glsl>
#include "signature_common.glsl"

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

// Bounded mirror mandala: 10 taps (5 wedge counts + clean + 2 seam + 2 motion).
// Blend adjacent EVEN wedge counts instead of rounding a live mid uniform.
// The central disc is protected; every mirror displacement is <=8% of width.
vec3 imageAt(vec2 p) {
    return texture(uImage, clamp(p * uUvScale + uUvOffset, 0.0, 1.0)).rgb;
}
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec3 mirrorAt(vec2 uv, vec2 centre, vec2 aspect, float k, float rotation,
    float ring, out float seam) {
    vec2 q = (uv - centre) * aspect;
    float r = length(q);
    float a = atan(q.y, q.x + 0.0000001) - rotation;
    float sector = 6.2831853 / k;
    float folded = abs(mod(a + sector * 0.5, sector) - sector * 0.5);
    float radius = mix(r, abs(r - 0.35), ring);
    vec2 target = vec2(cos(folded + rotation), sin(folded + rotation)) * radius;
    vec2 delta = target - q;
    delta *= min(1.0, 0.08 / max(length(delta), 0.000001));
    float border = min(folded, sector * 0.5 - folded) * r;
    float seamWidth = 0.012 * (0.8 + 0.4 * clamp(uLight, 0.0, 1.0));
    seam = 1.0 - smoothstep(0.0, seamWidth, border);
    seam = max(seam, ring * (1.0 - smoothstep(0.0, 0.015, abs(r - 0.35))));
    return imageAt(uv + delta / aspect);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec2 aspect = vec2(1.0, uSize.y / uSize.x);
    vec3 clean = imageAt(uv);
    float n = clamp(uNoise, 0.0, 1.0);
    float b = clamp(uBass, 0.0, 1.0);
    float md = clamp(uMid, 0.0, 1.0);
    float t = clamp(uTreble, 0.0, 1.0);
    float m = clamp(uMotion, 0.0, 1.0);
    float light = clamp(uLight, 0.0, 1.0) * 2.0 - 1.0;
    float phase = uSeed * 5.731;
    vec2 centre = 0.5 + 0.045 * vec2(sin(phase), cos(phase * 0.83));
    float radius = length((uv - centre) * aspect);
    float protect = smoothstep(0.16, 0.31, radius);
    // Bound motion sensitivity independently of the elapsed session time.
    float rotation = 0.25 * m * sin(uTime * 0.2)
        + 0.065 * n * sin(uv.y * 17.0 + phase + uTime * 0.23);
    float ring = smoothstep(0.15, 0.85, b);
    vec3 mirrored = vec3(0.0);
    float seams = 0.0;
    for (int i = 0; i < 5; i++) {
        float seam;
        vec3 sampleColor = mirrorAt(uv, centre, aspect, 6.0 + 2.0 * float(i),
            rotation, ring, seam);
        float weight = max(0.0, 1.0 - abs(md * 4.0 - float(i)));
        mirrored += weight * sampleColor;
        seams += weight * seam;
    }
    float strength = min(0.65, 0.65 * pow(n, 1.35) + 0.4 * md + 0.3 * b);
    vec3 color = mix(clean, mirrored, strength * protect);
    // Treble disperses only fine seam detail, not the whole image.
    float fine = 0.5 + 0.5 * sin(radius * 371.0 + phase);
    vec3 seamTint = mix(vec3(0.65, 0.82, 1.0), vec3(1.0, 0.72, 0.42),
        0.5 + 0.5 * light);
    float seamAmount = protect * seams * (0.1 * strength + 0.16 * t * fine);
    color *= 1.0 + seamAmount * seamTint;
    vec2 radial = (uv - centre) * aspect / max(radius, 0.000001);
    vec2 split = vec2(-radial.y, radial.x) * (0.012 * t) / aspect;
    vec3 dispersion = vec3(imageAt(uv + split).r, color.g,
        imageAt(uv - split).b);
    color = mix(color, dispersion, 0.75 * t * protect * seams);
    vec2 direction = vec2(uMotionDir.x, -uMotionDir.y) / aspect;
    vec3 moving = imageAt(uv - direction * 0.045 * m) * 0.65
        + imageAt(uv - direction * 0.022 * m) * 0.35;
    color = mix(color, moving, 0.65 * m);
    // Light controls seam width/colour and radial exposure, independently.
    color *= vec3(1.0 + 0.09 * light, 1.0 - 0.025 * light,
        1.0 - 0.12 * light);
    color *= 1.0 + 0.13 * light * cos(radius * 9.0);
    color *= min(1.0, 1.18 * luma(clean) / max(luma(color), 0.000001));
    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
