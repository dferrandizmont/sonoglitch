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

// Wet ink: 4 texture taps, including the clean detail and directional flow.
// All lengths are fractions of the output width. The current ABI is untiled.
vec3 imageAt(vec2 p) {
    return texture(uImage, clamp(p * uUvScale + uUvOffset, 0.0, 1.0)).rgb;
}

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

float field(vec2 p, float phase) {
    return (sin(p.x * 6.0 + phase) * cos(p.y * 4.8 - phase)
        + 0.5 * sin(p.x * 13.0 - phase) * cos(p.y * 10.4 + phase)
        + 0.25 * sin(p.x * 29.0 + phase) * cos(p.y * 23.2)) / 1.75;
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec2 aspect = vec2(1.0, uSize.y / uSize.x);
    vec2 p = uv * aspect;
    vec3 clean = imageAt(uv);
    float n = clamp(uNoise, 0.0, 1.0);
    float b = clamp(uBass, 0.0, 1.0);
    float md = clamp(uMid, 0.0, 1.0);
    float t = clamp(uTreble, 0.0, 1.0);
    float m = clamp(uMotion, 0.0, 1.0);
    float light = clamp(uLight, 0.0, 1.0) * 2.0 - 1.0;
    // Less than one turn keeps seeds zero and one distinct, too.
    float phase = uSeed * 5.731 + uTime * 0.13;
    vec2 flow = vec2(field(p * (1.0 + md), phase),
        field(p.yx * (1.0 + md) + 1.7, phase + 2.1));
    // Bass swells the broad tide; mid brings smaller ink eddies into its body.
    flow += b * 0.6 * vec2(sin(p.y * 4.0 + phase * 0.4),
        cos(p.x * 5.0 - phase * 0.4));
    vec2 warp = flow * (0.01 + 0.035 * n + 0.012 * b + 0.01 * md);
    warp *= min(1.0, 0.06 / max(length(warp), 0.000001));
    vec3 a = imageAt(uv + warp / aspect);
    vec3 c = imageAt(uv - warp * 0.65 / aspect);
    vec3 ink = max(a, c);
    float edge = abs(luma(a) - luma(c));
    ink *= 1.0 - 0.35 * edge * (0.4 + 0.6 * n);
    float wet = min(0.64, 0.64 * pow(n, 1.35) + 0.25 * b + 0.3 * md);
    vec3 color = mix(clean, ink, wet);
    vec2 direction = vec2(uMotionDir.x, -uMotionDir.y);
    vec3 dragged = imageAt(uv - direction * (0.048 * m) / aspect);
    color = mix(color, dragged, 0.6 * m);
    // Continuous fibres and pigment granulation: no pixel/seed hash jumps.
    float fibre = sin(p.x * 317.0 + sin(p.y * 83.0) + phase);
    float pigment = 0.5 + 0.5 * sin(p.x * 613.0 + phase)
        * cos(p.y * 577.0 - phase);
    color *= 1.0 - 0.25 * t * pigment * (1.0 - luma(clean));
    float paper = max(light, 0.0);
    float dense = max(-light, 0.0);
    color *= vec3(1.0 + 0.08 * paper - 0.15 * dense,
        1.0 - 0.02 * paper - 0.09 * dense,
        1.0 - 0.13 * paper + 0.02 * dense);
    color *= 1.0 + paper * 0.04 * fibre * luma(clean)
        - dense * 0.15 * (1.0 - luma(clean));
    // A wet maximum may lift a dark edge. Bound that lift against this pixel,
    // rather than against a frame average; black remains black without NaN.
    color *= min(1.0, 1.18 * luma(clean) / max(luma(color), 0.000001));
    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
