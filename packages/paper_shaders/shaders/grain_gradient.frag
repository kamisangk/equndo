#include <flutter/runtime_effect.glsl>

uniform vec2 u_resolution;
uniform float u_time;
uniform float u_pixelRatio;
uniform float u_scale;
uniform float u_rotation;
uniform float u_offsetX;
uniform float u_offsetY;
uniform float u_softness;
uniform float u_intensity;
uniform float u_noise;
uniform float u_shape;
uniform float u_colorsCount;
uniform vec4 u_colorBack;
uniform vec4 u_color0;
uniform vec4 u_color1;
uniform vec4 u_color2;
uniform vec4 u_color3;
uniform vec4 u_color4;
uniform vec4 u_color5;
uniform vec4 u_color6;
uniform sampler2D u_noiseTexture;

out vec4 fragColor;

#define TWO_PI 6.28318530718
#define PI 3.14159265358979323846

// --- simplex noise ---
vec3 permute(vec3 x) { return mod(((x * 34.0) + 1.0) * x, 289.0); }
float snoise(vec2 v) {
  vec4 C = vec4(0.211324865405187, 0.366025403784439,
    -0.577350269189626, 0.024390243902439);
  vec2 i = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1;
  i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod(i, 289.0);
  vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0))
    + i.x + vec3(0.0, i1.x, 1.0));
  vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy),
      dot(x12.zw, x12.zw)), 0.0);
  m = m * m;
  m = m * m;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
  vec3 g;
  g.x = a0.x * x0.x + h.x * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

// --- rotation ---
vec2 rotate(vec2 uv, float th) {
  float c = cos(th);
  float s = sin(th);
  return vec2(c * uv.x + s * uv.y, -s * uv.x + c * uv.y);
}

// --- texture randomizer ---
float randomR(vec2 p) {
  vec2 uv = floor(p) / 100. + .5;
  return texture(u_noiseTexture, fract(uv)).r;
}

// --- procedural hash ---
float hash11(float p) {
  p = fract(p * 0.3183099) + 0.1;
  p *= p + 19.19;
  return fract(p * p);
}

// --- value noise ---
float valueNoiseR(vec2 st) {
  vec2 i = floor(st);
  vec2 f = fract(st);
  float a = randomR(i);
  float b = randomR(i + vec2(1.0, 0.0));
  float c = randomR(i + vec2(0.0, 1.0));
  float d = randomR(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  float x1 = mix(a, b, u.x);
  float x2 = mix(c, d, u.x);
  return mix(x1, x2, u.y);
}

// --- fbm ---
vec4 fbmR(vec2 n0, vec2 n1, vec2 n2, vec2 n3) {
  float amplitude = 0.2;
  vec4 total = vec4(0.);
  for (int i = 0; i < 3; i++) {
    n0 = rotate(n0, 0.3);
    n1 = rotate(n1, 0.3);
    n2 = rotate(n2, 0.3);
    n3 = rotate(n3, 0.3);
    total.x += valueNoiseR(n0) * amplitude;
    total.y += valueNoiseR(n1) * amplitude;
    total.z += valueNoiseR(n2) * amplitude;
    total.w += valueNoiseR(n3) * amplitude;
    n0 *= 1.99;
    n1 *= 1.99;
    n2 *= 1.99;
    n3 *= 1.99;
    amplitude *= 0.6;
  }
  return total;
}

// --- truchet ---
vec2 truchet(vec2 uv, float idx) {
  idx = fract(((idx - .5) * 2.));
  if (idx > 0.75) {
    uv = vec2(1.0) - uv;
  } else if (idx > 0.5) {
    uv = vec2(1.0 - uv.x, uv.y);
  } else if (idx > 0.25) {
    uv = 1.0 - vec2(1.0 - uv.x, uv.y);
  }
  return uv;
}

// --- 获取颜色（替代数组索引）---
vec4 getColor(int i) {
  if (i == 0) return u_color0;
  if (i == 1) return u_color1;
  if (i == 2) return u_color2;
  if (i == 3) return u_color3;
  if (i == 4) return u_color4;
  if (i == 5) return u_color5;
  return u_color6;
}

void main() {
  // Flutter 中 FlutterFragCoord() 返回逻辑像素
  vec2 fragCoord = FlutterFragCoord().xy;

  float firstFrameOffset = 7.;
  float t = .1 * (u_time + firstFrameOffset);

  // --- 内联顶点着色器 UV 计算 ---
  // Flutter 无自定义顶点着色器，这里直接在 fragment shader 中计算
  // 简化版本：不需要 fit/origin/worldWidth 等 Web 概念
  vec2 uv = fragCoord / u_resolution;

  float r = u_rotation * PI / 180.;
  float cr = cos(r);
  float sr = sin(r);
  // graphicRotation = mat2(cr, sr, -sr, cr)
  vec2 graphicOffset = vec2(-u_offsetX, u_offsetY);

  // 中心化坐标
  vec2 centered = uv - 0.5;
  float aspect = u_resolution.x / u_resolution.y;

  // objectUV: 用于形状 4-7（基于对象的形状）
  // 应用缩放、旋转、偏移
  vec2 objectUV = centered;
  objectUV.x *= aspect;
  // 手动 mat2 * vec2（避免 Impeller 兼容性问题）
  objectUV = vec2(cr * objectUV.x + sr * objectUV.y, -sr * objectUV.x + cr * objectUV.y);
  objectUV /= u_scale;
  objectUV -= graphicOffset;

  // patternUV: 用于形状 1-3（基于图案的形状）
  vec2 patternUV = centered;
  patternUV.x *= aspect;
  patternUV = vec2(cr * patternUV.x + sr * patternUV.y, -sr * patternUV.x + cr * patternUV.y);
  patternUV /= u_scale;
  patternUV -= graphicOffset;
  patternUV *= TWO_PI;

  // --- shape_uv 和 grain_uv 计算 ---
  vec2 shape_uv = vec2(0.);
  vec2 grain_uv = vec2(0.);

  if (u_shape > 3.5) {
    shape_uv = objectUV;
    grain_uv = shape_uv;

    // 应用逆变换到 grain_uv（手动转置矩阵）
    // transpose(mat2(cr,sr,-sr,cr)) = mat2(cr,-sr,sr,cr)
    grain_uv = vec2(cr * grain_uv.x + (-sr) * grain_uv.y, sr * grain_uv.x + cr * grain_uv.y);
    grain_uv *= u_scale;
    grain_uv -= graphicOffset;
    grain_uv *= u_resolution;
    grain_uv *= .7;
  } else {
    shape_uv = .5 * patternUV;
    grain_uv = 100. * patternUV;

    // 应用逆变换到 grain_uv
    grain_uv = vec2(cr * grain_uv.x + (-sr) * grain_uv.y, sr * grain_uv.x + cr * grain_uv.y);
    grain_uv *= u_scale;
    grain_uv -= graphicOffset * u_resolution / u_resolution;
    grain_uv *= 1.6;
  }

  // --- 形状计算 ---
  float shape = 0.;

  if (u_shape < 1.5) {
    // Wave
    float wave = cos(.5 * shape_uv.x - 4. * t) * sin(1.5 * shape_uv.x + 2. * t) * (.75 + .25 * cos(6. * t));
    shape = 1. - smoothstep(-1., 1., shape_uv.y + wave);

  } else if (u_shape < 2.5) {
    // Dots
    float stripeIdx = floor(2. * shape_uv.x / TWO_PI);
    float rand = hash11(stripeIdx * 100.);
    rand = sign(rand - .5) * pow(4. * abs(rand), .3);
    shape = sin(shape_uv.x) * cos(shape_uv.y - 5. * rand * t);
    shape = pow(abs(shape), 4.);

  } else if (u_shape < 3.5) {
    // Truchet
    float n2 = valueNoiseR(shape_uv * .4 - 3.75 * t);
    shape_uv.x += 10.;
    shape_uv *= .6;

    vec2 tile = truchet(fract(shape_uv), randomR(floor(shape_uv)));

    float distance1 = length(tile);
    float distance2 = length(tile - vec2(1.));

    n2 -= .5;
    n2 *= .1;
    shape = smoothstep(.2, .55, distance1 + n2) * (1. - smoothstep(.45, .8, distance1 - n2));
    shape += smoothstep(.2, .55, distance2 + n2) * (1. - smoothstep(.45, .8, distance2 - n2));

    shape = pow(shape, 1.5);

  } else if (u_shape < 4.5) {
    // Corners
    shape_uv *= .6;
    vec2 outer = vec2(.5);

    vec2 bl = smoothstep(vec2(0.), outer, shape_uv + vec2(.1 + .1 * sin(3. * t), .2 - .1 * sin(5.25 * t)));
    vec2 tr = smoothstep(vec2(0.), outer, 1. - shape_uv);
    shape = 1. - bl.x * bl.y * tr.x * tr.y;

    shape_uv = -shape_uv;
    bl = smoothstep(vec2(0.), outer, shape_uv + vec2(.1 + .1 * sin(3. * t), .2 - .1 * cos(5.25 * t)));
    tr = smoothstep(vec2(0.), outer, 1. - shape_uv);
    shape -= bl.x * bl.y * tr.x * tr.y;

    shape = 1. - smoothstep(0., 1., shape);

  } else if (u_shape < 5.5) {
    // Ripple
    shape_uv *= 2.;
    float dist = length(.4 * shape_uv);
    float waves = sin(pow(dist, 1.2) * 5. - 3. * t) * .5 + .5;
    shape = waves;

  } else if (u_shape < 6.5) {
    // Blob
    float t2 = t * 2.;

    vec2 f1_traj = .25 * vec2(1.3 * sin(t2), .2 + 1.3 * cos(.6 * t2 + 4.));
    vec2 f2_traj = .2 * vec2(1.2 * sin(-t2), 1.3 * sin(1.6 * t2));
    vec2 f3_traj = .25 * vec2(1.7 * cos(-.6 * t2), cos(-1.6 * t2));
    vec2 f4_traj = .3 * vec2(1.4 * cos(.8 * t2), 1.2 * sin(-.6 * t2 - 3.));

    // clamp(0,1,x) 修正为 max(1-x, 0) 形式
    shape = .5 * pow(max(1. - length(shape_uv + f1_traj), 0.), 5.);
    shape += .5 * pow(max(1. - length(shape_uv + f2_traj), 0.), 5.);
    shape += .5 * pow(max(1. - length(shape_uv + f3_traj), 0.), 5.);
    shape += .5 * pow(max(1. - length(shape_uv + f4_traj), 0.), 5.);

    shape = smoothstep(.0, .9, shape);
    float edge = smoothstep(.25, .3, shape);
    shape = mix(.0, shape, edge);

  } else {
    // Sphere
    shape_uv *= 2.;
    float d = 1. - pow(length(shape_uv), 2.);
    vec3 pos = vec3(shape_uv, sqrt(max(d, 0.)));
    vec3 lightPos = normalize(vec3(cos(1.5 * t), .8, sin(1.25 * t)));
    shape = .5 + .5 * dot(lightPos, pos);
    shape *= step(0., d);
  }

  // --- 噪声和扭曲 ---
  float baseNoise = snoise(grain_uv * .5);
  vec4 fbmVals = fbmR(
    .002 * grain_uv + 10.,
    .003 * grain_uv,
    .001 * grain_uv,
    rotate(.4 * grain_uv, 2.)
  );
  float grainDist = baseNoise * snoise(grain_uv * .2) - fbmVals.x - fbmVals.y;
  float rawNoise = .75 * baseNoise - fbmVals.w - fbmVals.z;
  float nse = clamp(rawNoise, 0., 1.);

  shape += u_intensity * 2. / u_colorsCount * (grainDist + .5);
  shape += u_noise * 10. / u_colorsCount * nse;

  // fwidth 在 Impeller 上可能不可用，用基于分辨率的估算值
  float aa = 1.0 / max(u_resolution.x, u_resolution.y);

  shape = clamp(shape - .5 / u_colorsCount, 0., 1.);
  float totalShape = smoothstep(0., u_softness + 2. * aa, clamp(shape * u_colorsCount, 0., 1.));
  float mixer = shape * (u_colorsCount - 1.);

  int cntStop = int(u_colorsCount) - 1;
  vec4 gradient = getColor(0);
  gradient.rgb *= gradient.a;
  for (int i = 1; i < 7; i++) {
    if (i <= cntStop) {
      float localT = clamp(mixer - float(i - 1), 0., 1.);
      localT = smoothstep(.5 - .5 * u_softness - aa, .5 + .5 * u_softness + aa, localT);

      vec4 c = getColor(i);
      c.rgb *= c.a;
      gradient = mix(gradient, c, localT);
    }
  }

  vec3 color = gradient.rgb * totalShape;
  float opacity = gradient.a * totalShape;

  vec3 bgColor = u_colorBack.rgb * u_colorBack.a;
  color = color + bgColor * (1.0 - opacity);
  opacity = opacity + u_colorBack.a * (1.0 - opacity);

  fragColor = vec4(color, opacity);
}
