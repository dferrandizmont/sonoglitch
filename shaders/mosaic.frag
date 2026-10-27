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

// Textured print cells: 4 taps (clean, 48-cell grid, bass grid, motion).
// Fixed grids crossfade for bass: moving a floor() boundary with a live
// uniform would pop. Seed changes only the continuous in-cell jitter.
vec3 imageAt(vec2 p) {
    return texture(uImage, clamp(p * uUvScale + uUvOffset, 0.0, 1.0)).rgb;
}
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec3 cellAt(vec2 uv, vec2 aspect, float count, float jitter,
    float phase, out float border) {
    vec2 grid = uv * aspect * count;
    vec2 cell = floor(grid);
    vec2 inside = fract(grid);
    vec2 offset = 0.5 + 0.35 * jitter * vec2(
        sin(dot(cell, vec2(13.17, 7.31)) + phase),
        cos(dot(cell, vec2(5.73, 19.43)) - phase));
    vec2 nearest = min(inside, 1.0 - inside);
    border = min(nearest.x, nearest.y);
    return imageAt((cell + clamp(offset, 0.15, 0.85)) / (aspect * count));
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
    float phase = uSeed * 5.731 + uTime * 0.17;
    float border48;
    float borderBass;
    vec3 small = cellAt(uv, aspect, 48.0, n, phase, border48);
    vec3 large = cellAt(uv, aspect, 32.0, n, phase, borderBass);
    float pulse = b * (0.8 + 0.2 * sin(phase * 0.3));
    vec3 cells = mix(small, large, pulse);
    float border = mix(border48, borderBass, pulse);
    float edge = 1.0 - smoothstep(0.015, 0.13 - 0.08 * md, border);
    // Duotone is a translucent ink layer, retaining source chroma/detail.
    float value = luma(cells);
    vec3 darkInk = mix(vec3(0.06, 0.07, 0.10), vec3(0.12, 0.065, 0.035),
        0.5 + 0.5 * light);
    vec3 paper = mix(vec3(0.82, 0.93, 1.0), vec3(1.0, 0.94, 0.82),
        0.5 + 0.5 * light);
    cells = mix(cells, mix(darkInk, paper, value), 0.38);
    cells *= 1.0 - edge * (0.08 + 0.24 * md);
    float strength = min(0.65, 0.65 * pow(n, 1.35) + 0.42 * b + 0.35 * md);
    // Treble exposes original detail through fine, continuous dissolve holes.
    float dissolve = 0.5 + 0.5 * sin(uv.x * 467.0 + phase)
        * cos(uv.y * aspect.y * 431.0 - phase);
    float wet = strength * (1.0 - 0.75 * t * dissolve);
    vec3 color = mix(clean, cells, wet);
    // Also readable with no other signal: pigment pinholes modulate texture.
    color *= 1.0 - 0.16 * t * dissolve;
    vec2 direction = vec2(uMotionDir.x, -uMotionDir.y);
    float shear = 0.028 + 0.018 * uv.y;
    vec3 rolled = imageAt(uv - direction * shear * m / aspect);
    color = mix(color, rolled, 0.7 * m);
    color *= mix(vec3(1.0), paper, abs(light) * 0.65);
    color *= 1.0 + light * (0.16 * luma(clean) - 0.08)
        - abs(light) * 0.13 * edge;
    color *= min(1.0, 1.18 * luma(clean) / max(luma(color), 0.000001));
    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
