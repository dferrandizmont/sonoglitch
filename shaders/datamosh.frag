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

float luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 sampleImage(vec2 p) {
    return texture(uImage, clamp(p * uUvScale + uUvOffset, 0.0, 1.0)).rgb;
}

// Retain texture even at the strongest setting, and cap local brightening.
vec3 finishColor(vec3 color, vec3 source) {
    float ceiling = luma(source) * 1.18;
    color *= min(1.0, ceiling / max(luma(color), 0.00001));
    return clamp(color, 0.0, 1.0);
}

// Lost keyframe: four texture taps, no frame history or stored camera data.
// Exactly one of each eight macroblocks is damaged (at most 12.5% area).
// The spatial hash is constant; all time, band and seed modulation is smooth.
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec2 widthUnits = vec2(1.0, uSize.x / uSize.y);
    vec3 source = sampleImage(uv);
    vec2 grid = uv / widthUnits * 64.0;
    vec2 block = floor(grid);
    vec2 cell = fract(grid);
    float lane = floor(hash(vec2(floor(block.x / 8.0), block.y)) * 8.0);
    float selected = 1.0 - step(0.5, abs(mod(block.x, 8.0) - lane));
    float feather = mix(0.24, 0.025, uTreble);
    vec2 edge = smoothstep(vec2(0.0), vec2(feather), min(cell, 1.0 - cell));
    float mask = selected * edge.x * edge.y;
    float energy = 1.0 - (1.0 - uNoise) * (1.0 - 0.85 * uBass)
        * (1.0 - 0.85 * uMid) * (1.0 - 0.75 * uTreble);
    float phase = 6.2831853 * (hash(block) + uSeed)
        + sin(uTime * 0.17) * (0.12 + 0.3 * uBass);
    vec2 vector = vec2(cos(phase), sin(phase));
    // Bass produces a broad, slowly flowing vector; mids stretch the drip.
    float slow = sin(grid.y * 0.12 + uTime * 0.11 + uSeed * 5.0);
    vector = mix(vector, vec2(slow, 0.7), 0.65 * uBass);
    vector *= 0.008 + 0.025 * uBass + 0.010 * uNoise;
    vector.y += 0.012 * uMid * cell.y * cell.y;
    vector *= min(1.0, 0.030 / max(length(vector), 0.00001));
    // Motion feeds a skewed frame into both the current block and its ghost.
    vec2 shear = -vec2(uMotionDir.x, -uMotionDir.y)
        * (0.012 * uMotion * (0.5 + uv.y));
    vec3 moving = sampleImage(uv + shear * widthUnits);
    vec3 blockColor = sampleImage(uv + (shear - vector) * widthUnits);
    vec3 ghost = sampleImage(uv + (shear - 0.5 * vector) * widthUnits);
    float mood = 2.0 * uLight - 1.0;
    ghost *= vec3(1.0 + 0.13 * mood, 0.97, 1.0 - 0.13 * mood);
    vec3 damaged = mix(blockColor, ghost, 0.35 + 0.12 * uMid);
    vec3 color = mix(moving, damaged, 0.72 * energy * mask);
    // Light changes ghost ink and compression contrast even in a quiet room.
    float contrast = 1.0 - 0.18 * max(mood, 0.0) + 0.15 * min(mood, 0.0);
    color = mix(color, vec3(luma(color)), 0.12 * max(mood, 0.0));
    color = color * contrast * vec3(1.0 + 0.09 * mood, 1.0, 1.0 - 0.12 * mood);
    fragColor = vec4(finishColor(color, source), 1.0);
}
