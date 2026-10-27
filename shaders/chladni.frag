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

// Vibrating square plate: two taps (reference + vibrating image).
// Fractional modes avoid the discontinuities of rounded band energies.
// Unequal resting modes avoid the identically-zero equal-mode plate.
void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec2 widthUnits = vec2(1.0, uSize.x / uSize.y);
    vec3 source = sampleImage(uv);
    float angle = 0.06 * uMotion;
    vec2 q = uv - 0.5;
    q = mat2(cos(angle), -sin(angle), sin(angle), cos(angle)) * q;
    q += 0.5 + vec2(0.12 * sin(uSeed * 5.0), 0.11 * cos(uSeed * 4.0));
    float a = 2.0 + 3.0 * uBass;
    // Keep the modes separated for every continuous band combination.
    float b = a + 1.0 + 5.0 * uMid;
    float x = q.x * 3.14159265;
    float y = q.y * 3.14159265;
    float f = sin(a * x) * sin(b * y) - sin(b * x) * sin(a * y);
    f += 0.35 * uTreble * sin((a + b + 3.0) * x) * sin((a - b - 2.0) * y);
    float mood = 2.0 * uLight - 1.0;
    float width = 0.028 + 0.008 * max(mood, 0.0);
    float sand = 1.0 - smoothstep(0.0, width, abs(f));
    float energy = 1.0 - (1.0 - uNoise) * (1.0 - uBass)
        * (1.0 - uMid) * (1.0 - uTreble) * (1.0 - abs(mood));
    float grains = 0.75 + 0.25 * sin(q.x * 1200.0 + uSeed * 17.0)
        * sin(q.y * 1150.0 - uSeed * 13.0);
    float deposit = sand * energy * grains;
    // A tiny local vibration; the separate directional feed makes motion legible.
    vec2 vibration = vec2(cos(x * a), sin(y * b))
        * (0.0015 * deposit * sin(uTime * 6.0 + f * 12.0));
    vec2 feed = -vec2(uMotionDir.x, -uMotionDir.y)
        * (0.015 * uMotion * (0.6 + 0.4 * uv.y));
    vec3 moving = sampleImage(uv + (feed + vibration) * widthUnits);
    vec3 sandInk = mix(vec3(0.64, 0.70, 0.78), vec3(1.0, 0.91, 0.68), uLight);
    // Multiplicative mineral ink preserves the subject under every node.
    vec3 mineral = moving * (0.45 + 0.55 * sandInk);
    mineral = mix(mineral, vec3(luma(moving)) * sandInk, 0.40);
    vec3 color = mix(moving, mineral, 0.82 * deposit);
    // Illumination changes node relief and shadow density without a white flash.
    color *= mix(1.0, 0.86 + 0.10 * luma(moving), abs(mood));
    color *= vec3(1.0 + 0.07 * mood, 1.0, 1.0 - 0.09 * mood);
    fragColor = vec4(finishColor(color, source), 1.0);
}
