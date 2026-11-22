// Topographic contour lines over a slowly drifting noise relief.
//
// Every pixel finds how far it is from the nearest contour in screen pixels
// (the level distance divided by the relief's slope), so lines stay one pixel
// wide on any slope and anti-alias without a grid. The slope is analytic:
// each noise layer returns its derivatives with its value, so the relief is
// evaluated once per pixel. Every fifth line is an index contour, wider and
// brighter.

#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;      // logical size
uniform float uDpr;      // device pixel ratio
uniform vec2 uDrift0F;   // octave 0 fractional drift [0, 1) from float64
uniform vec2 uDrift0I;   // octave 0 integer cell drift (exact up to 2^24)
uniform vec2 uDrift1F;   // octave 1 fractional drift (+ 7.3)
uniform vec2 uDrift1I;   // octave 1 integer cell drift
uniform vec2 uDrift2F;   // octave 2 fractional drift (- 3.1)
uniform vec2 uDrift2I;   // octave 2 integer cell drift
uniform float uRise;     // 0 flat ground .. 1 full relief
uniform float uLevels;   // contour lines per unit of height
uniform float uScale;    // logical pixels per hill
uniform vec3 uPeak;      // cursor peak: x, y, height (0..1)
uniform vec4 uWave;      // click wave: x, y, age (s), strength (0..1)
uniform vec3 uColor;     // line colour

out vec4 fragColor;

const float kPeakHeight = 0.5;
const float kPeakRadius = 72.0;
const float kInvPeakRadius = 1.0 / kPeakRadius;
const float kNegInvPeakRadiusLog2 = -1.4426950408889634 / kPeakRadius;
const float kWaveSpeed = 210.0;  // logical px per second
const float kWaveLife = 2.6;     // seconds
const float kInvWaveLife = 1.0 / kWaveLife;
const float kWaveWidth = 26.0;
const float kWaveHeight = 0.32;
const float kWaveW2 = kWaveWidth * kWaveWidth;
const float kNegInvWaveW2Log2 = -1.4426950408889634 / kWaveW2;
const float kEdge = 56.0;        // lines fade out this close to the edges
const float kLineAlpha = 0.2;
const float kIndexAlpha = 0.45;
const float kLineHalfWidth = 0.4;
const float kIndexHalfWidth = 0.75;
const vec3 kOct1 = vec3(0.25, 0.475, 0.475);
const vec3 kOct2 = vec3(0.10, 0.37, 0.37);

// Hash from pre-reduced fract(p.xyx * vec3(0.1031, 0.1030, 0.0973)) so the
// four corners of a noise cell share x/y/z reductions (half as many fract()).
vec2 hashFromP3(vec3 p3) {
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}

// 2D gradient noise, roughly -0.7..0.7: value in x, d/dp in yz.
// Splits cell index (iOffset) from fractional drift (p) so long drift times
// keep full float32 sub-pixel precision with zero seam.
vec3 noised(vec2 p, vec2 iOffset) {
  vec2 i = floor(p);
  vec2 f = p - i;
  vec2 u = f * f * (3.0 - 2.0 * f);
  vec2 du = 6.0 * f * (1.0 - f);
  vec2 cell0 = i + iOffset;
  vec2 cell1 = cell0 + 1.0;
  float x0 = fract(cell0.x * 0.1031);
  float x1 = fract(cell1.x * 0.1031);
  float y0 = fract(cell0.y * 0.1030);
  float y1 = fract(cell1.y * 0.1030);
  float z0 = fract(cell0.x * 0.0973);
  float z1 = fract(cell1.x * 0.0973);
  vec2 ga = hashFromP3(vec3(x0, y0, z0));
  vec2 gb = hashFromP3(vec3(x1, y0, z1));
  vec2 gc = hashFromP3(vec3(x0, y1, z0));
  vec2 gd = hashFromP3(vec3(x1, y1, z1));
  float va = dot(ga, f);
  float vb = dot(gb, f - vec2(1.0, 0.0));
  float vc = dot(gc, f - vec2(0.0, 1.0));
  float vd = dot(gd, f - vec2(1.0, 1.0));
  float k0 = vb - va;
  float k1 = vc - va;
  float k2 = vd - vc - k0;
  return vec3(
    va + u.x * k0 + u.y * k1 + u.x * u.y * k2,
    mix(mix(ga, gb, u.x), mix(gc, gd, u.x), u.y)
      + du * (u.yx * k2 + vec2(k0, k1)));
}

// The relief at px (logical pixels): height in x, slope per pixel in yz.
vec3 relief(vec2 px) {
  float invScale = 1.0 / uScale;
  vec2 q = px * invScale;
  // Layers drifting in different directions reshape the relief rather
  // than sliding it. Each layer's slope is scaled by its frequency.
  vec3 h = 0.65 * noised(q + uDrift0F, uDrift0I)
         + kOct1 * noised(q * 1.9 + uDrift1F, uDrift1I)
         + kOct2 * noised(q * 3.7 + uDrift2F, uDrift2I);
  h.yz *= invScale;

  // The cursor peak: sharp at the summit, so its rings tighten there.
  // Skipped (uniformly, for every pixel) while there is none.
  if (uPeak.z > 0.001) {
    vec2 dp = px - uPeak.xy;
    float d = max(length(dp), 1e-3);
    float peak = uPeak.z * kPeakHeight * exp2(d * kNegInvPeakRadiusLog2);
    h += vec3(peak, (-peak * kInvPeakRadius) * dp / d);
  }

  // The click wave: a crest with a trough behind it, fading as it travels.
  // Outside the active annulus both Gaussians are < 1e-7, so skip exp2/sqrt.
  float age = uWave.z;
  if (uWave.w > 0.0 && age < kWaveLife) {
    vec2 dw2 = px - uWave.xy;
    float lenSq = dot(dw2, dw2);
    float front = age * kWaveSpeed;
    float rMin = max(front - 6.0 * kWaveWidth, 0.0);
    float rMax = front + 4.0 * kWaveWidth;
    if (lenSq >= rMin * rMin && lenSq <= rMax * rMax) {
      float len = max(sqrt(lenSq), 1e-3);
      float dw = len - front;
      float back = dw + 2.0 * kWaveWidth;
      float crest = exp2((dw * dw) * kNegInvWaveW2Log2);
      float trough = exp2((back * back) * kNegInvWaveW2Log2);
      float life = 1.0 - age * kInvWaveLife;
      float amp = uWave.w * kWaveHeight * life * life;
      float slope = (-2.0 / kWaveW2) * (dw * crest - 0.8 * back * trough);
      h += amp * vec3(crest - 0.8 * trough, slope * dw2 / len);
    }
  }

  // Rising from flat ground: lines bloom out from the middle level.
  return h * uRise;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 edge = min(p, uSize - p);
  float minEdge = min(edge.x, edge.y);
  if (minEdge <= 0.0 || uRise <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }

  float e = 1.0 / uDpr;  // one device pixel

  vec3 h = relief(p);
  // Half a level of offset keeps flat ground between two lines.
  float v = h.x * uLevels + 0.5;
  float slope = max(length(h.yz) * uLevels, 1e-4);

  float k = floor(v + 0.5);
  float dist = abs(v - k) / slope;  // logical px to the nearest line
  bool index = mod(k, 5.0) == 0.0;
  float half_w = index ? kIndexHalfWidth : kLineHalfWidth;
  float line = 1.0 - smoothstep(half_w - 0.5 * e, half_w + 0.5 * e, dist);

  // Where lines crowd closer than ~2px they would merge into a fill.
  line *= 1.0 - smoothstep(0.35, 0.6, slope);

  float fade = smoothstep(0.0, kEdge, minEdge);

  float a = line * fade * uRise * (index ? kIndexAlpha : kLineAlpha);
  fragColor = vec4(uColor * a, a);
}
