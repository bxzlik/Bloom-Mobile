#version 460 core

// My Wave's living circle: three soft discs of noise, outer to inner, each with
// a glowing rim that wanders, and spikes along the edge. Output is
// premultiplied, over nothing: the page shows around it.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;  // seconds of motion, sped up while playing
uniform float uZoom;  // the circle's size in the square: smaller = bigger circle
uniform vec3 uCol0;   // outer disc
uniform vec3 uCol1;
uniform vec3 uCol2;   // inner disc

out vec4 fragColor;

// Simplex noise, 3D: Ian McEwan, Ashima Arts / Stefan Gustavson (MIT).
vec4 permute(vec4 x) { return mod(((x * 34.0) + 1.0) * x, 289.0); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v)
{
    const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

    vec3 i = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);
    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);
    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + 2.0 * C.xxx;
    vec3 x3 = x0 - 1.0 + 3.0 * C.xxx;

    i = mod(i, 289.0);
    vec4 p = permute(permute(permute(i.z + vec4(0.0, i1.z, i2.z, 1.0))
                             + i.y + vec4(0.0, i1.y, i2.y, 1.0))
                     + i.x + vec4(0.0, i1.x, i2.x, 1.0));

    vec3 ns = 0.142857142857 * D.wyz - D.xzx;
    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);
    vec4 x = x_ * ns.x + ns.yyyy;
    vec4 y = y_ * ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);
    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);
    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));
    vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);
    vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

vec2 rotate(vec2 p, float a)
{
    float s = sin(a), c = cos(a);
    return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// How far the rim reaches out at this angle: a slow swell and a few soft
// tongues (ridges of noise), read on a circle, so there is no seam at ±π.
float spikes(float angle)
{
    vec2 c = vec2(cos(angle), sin(angle));
    float swell = snoise(vec3(c * 1.5, uTime * 0.03)) * 0.5 + 0.5;
    float ridge = 1.0 - abs(snoise(vec3(c * 2.0 + 3.1, uTime * 0.02)));
    return 0.06 + 0.1 * swell + 0.12 * pow(ridge, 8.0);
}

// One disc: i = 0 outer … 2 inner. A soft fill whose edge is noise, a bright
// line on that edge, cut off where the spikes end.
vec4 disc(vec2 uv, float len, float wobble, float spark, float i, vec3 col, vec3 turn)
{
    float off = 1.57 * i;
    float blob = 0.95 - 0.15 * i + 0.3 * wobble;
    float span = 0.8 - 0.2 * i;
    float reach = (1.0 - 0.3 * i) * spark;
    float outer = blob + 0.5 * span + reach;
    if (len >= outer)
        return vec4(0.0);

    vec2 p = uv + rotate(turn.xy, uTime * turn.z);
    float r = length(p);
    float rim = clamp(snoise(vec3(p * 1.2 + off, uTime * 0.5 + off)) * 0.5 + 0.5, 0.0, 1.0);

    float a = (1.0 - smoothstep(rim, rim + 1.1 + sin(uTime + off), r))
            * (1.0 - smoothstep(0.5, outer, len));
    float glow = 0.15 * (1.0 - 0.75 * sin(2.0 * uTime + 0.5 * off))
               / (1.0 + 11.0 * abs(r - rim));
    return vec4(clamp(col + glow, 0.0, 1.0), a);
}

void main()
{
    vec2 q = FlutterFragCoord().xy / uSize * 2.0 - 1.0;
    vec2 uv = vec2(q.x, -q.y) / uZoom;
    float len = length(uv);

    float wobble = clamp(snoise(vec3(uv * 1.2, uTime * 0.5)), -1.0, 1.0);
    float spark = spikes(atan(uv.y, uv.x));

    vec4 c = vec4(0.0);
    vec4 d = disc(uv, len, wobble, spark, 0.0, uCol0, vec3(-0.3, 0.3, 0.2));
    c.rgb = mix(c.rgb, d.rgb, d.a);
    c.a = max(c.a, d.a);
    d = disc(uv, len, wobble, spark, 1.0, uCol1, vec3(-0.3, -0.3, -0.2));
    c.rgb = mix(c.rgb, d.rgb, d.a);
    c.a = max(c.a, d.a);
    d = disc(uv, len, wobble, spark, 2.0, uCol2, vec3(-0.3, -0.3, 0.2));
    c.rgb = mix(c.rgb, d.rgb, d.a);
    c.a = max(c.a, d.a);

    // The square's corners: long spikes fade before its edge instead of being cut.
    fragColor = c * (1.0 - smoothstep(0.8, 1.0, length(q)));
}
