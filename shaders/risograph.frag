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

// Two ink screens: three taps (reference + each misregistered ink).
// Two dots of radius <= 0.17 cover at most 2*pi*0.17^2 = 18.2%.
// The screen has 60 cells across the short side, independently of resolution.
float inkDot(vec2 screen, float radius) {
    vec2 cell = fract(screen) - 0.5;
    return 1.0 - smoothstep(radius * 0.65, radius, length(cell));
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec2 widthUnits = vec2(1.0, uSize.x / uSize.y);
    vec3 source = sampleImage(uv);
    float energy = 1.0 - (1.0 - uNoise) * (1.0 - 0.85 * uBass)
        * (1.0 - 0.85 * uMid) * (1.0 - 0.85 * uTreble);
    float mood = 2.0 * uLight - 1.0;
    vec2 feed = -vec2(uMotionDir.x, -uMotionDir.y)
        * (0.014 * uMotion * (0.4 + uv.y));
    vec2 registerOffset = vec2(0.004 + 0.006 * uNoise, 0.008 * uMid);
    vec3 blueSource = sampleImage(uv + (feed + registerOffset) * widthUnits);
    vec3 warmSource = sampleImage(uv + (feed - registerOffset) * widthUnits);
    float angle = 0.78539816 + 0.18 * sin(uSeed * 6.0);
    vec2 q = uv * uSize / min(uSize.x, uSize.y);
    q.x += 0.02 * uMotion * q.y;
    vec2 screen = mat2(cos(angle), -sin(angle), sin(angle), cos(angle)) * q * 60.0;
    screen += vec2(uSeed * 3.7, uSeed * 2.3);
    float blueRadius = 0.11 + 0.06 * sqrt(clamp(luma(blueSource)
        * (0.75 + 0.25 * uBass), 0.0, 1.0));
    float warmRadius = 0.11 + 0.06 * sqrt(clamp((1.0 - luma(warmSource))
        * (0.75 + 0.25 * uBass), 0.0, 1.0));
    float blue = inkDot(screen + registerOffset * 60.0, blueRadius);
    float warm = inkDot(screen - registerOffset * 60.0, warmRadius);
    float fiber = 0.75 + 0.25 * sin(q.x * 1770.0 + uSeed * 9.0)
        * sin(q.y * 1930.0 - uSeed * 7.0);
    blue *= mix(1.0, fiber, uTreble);
    warm *= mix(1.0, fiber, uTreble);
    vec3 blueInk = vec3(0.10, 0.25, 0.62);
    vec3 warmInk = vec3(0.88, 0.22, 0.18);
    vec3 color = source;
    // Ink is translucent: no solid colour tiles, and underlying texture survives.
    color = mix(color, source * (0.30 + 0.70 * blueInk),
        energy * blue * (0.68 - 0.20 * mood));
    color = mix(color, source * (0.30 + 0.70 * warmInk),
        energy * warm * (0.68 + 0.20 * mood));
    // Crooked paper feed remains visible with noise/bands at zero.
    vec3 feedColor = mix(blueSource, warmSource, 0.5);
    color += uMotion * 0.65 * (feedColor - source);
    float paper = abs(mood) * (0.12 + 0.48 * max(mood, 0.0));
    vec3 paperGrade = source * vec3(0.96, 0.94, 0.89);
    paperGrade = mix(paperGrade, vec3(luma(source)) * vec3(1.0, 0.78, 0.63),
        max(mood, 0.0) * 0.55);
    paperGrade *= 0.76 + 0.22 * luma(source);
    color = mix(color, paperGrade, paper);
    // In a quiet room light still selects a blue or warm ink balance.
    color *= vec3(1.0 + 0.13 * mood, 1.0 - 0.05 * abs(mood), 1.0 - 0.13 * mood);
    fragColor = vec4(finishColor(color, source), 1.0);
}
