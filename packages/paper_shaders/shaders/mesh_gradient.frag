#include <flutter/runtime_effect.glsl>

uniform vec2 u_resolution;
uniform float u_time;
uniform float u_pixelRatio;
uniform float u_scale;
uniform float u_rotation;
uniform float u_offsetX;
uniform float u_offsetY;
uniform float u_colorsCount;
uniform float u_distortion;
uniform float u_swirl;
uniform vec4 u_colorBack;
uniform vec4 u_color0;
uniform vec4 u_color1;
uniform vec4 u_color2;
uniform vec4 u_color3;
uniform vec4 u_color4;
uniform vec4 u_color5;
uniform vec4 u_color6;

out vec4 fragColor;

#define PI 3.14159265358979323846

// --- 旋转 ---
vec2 rotate2d(vec2 uv, float th) {
  float c = cos(th);
  float s = sin(th);
  return vec2(c * uv.x + s * uv.y, -s * uv.x + c * uv.y);
}

// --- 程序化哈希 ---
float hash21(vec2 p) {
  p = fract(p * vec2(0.3183099, 0.3678794)) + 0.1;
  p += dot(p, p + 19.19);
  return fract(p.x * p.y);
}

// --- value noise ---
float valueNoise(vec2 st) {
  vec2 i = floor(st);
  vec2 f = fract(st);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  float x1 = mix(a, b, u.x);
  float x2 = mix(c, d, u.x);
  return mix(x1, x2, u.y);
}

// --- 获取颜色 ---
vec4 getColor(int i) {
  if (i == 0) return u_color0;
  if (i == 1) return u_color1;
  if (i == 2) return u_color2;
  if (i == 3) return u_color3;
  if (i == 4) return u_color4;
  if (i == 5) return u_color5;
  return u_color6;
}

// --- 计算颜色点的动画位置 ---
vec2 getPosition(int i, float t) {
  float a = float(i) * .37;
  float b = .6 + fract(float(i) / 3.) * .9;
  float c2 = .8 + fract(float(i + 1) / 4.);
  float x = sin(t * b + a);
  float y = cos(t * c2 + a * 1.5);
  return .5 + .5 * vec2(x, y);
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / u_resolution;

  // 应用缩放和偏移（简单变换）
  float r = u_rotation * PI / 180.;
  float cr = cos(r);
  float sr = sin(r);

  vec2 centered = uv - 0.5;
  centered = vec2(cr * centered.x + sr * centered.y, -sr * centered.x + cr * centered.y);
  centered /= u_scale;
  centered -= vec2(-u_offsetX, u_offsetY);
  uv = centered + 0.5;

  float firstFrameOffset = 41.5;
  float t = .5 * (u_time + firstFrameOffset);

  // --- 有机扭曲 ---
  float radius = smoothstep(0., 1., length(uv - .5));
  float center = 1. - radius;

  // 展开为 2 次迭代（避免 float 循环变量）
  uv.x += u_distortion * center * sin(t + .4 * smoothstep(.0, 1., uv.y)) * cos(.2 * t + 2.4 * smoothstep(.0, 1., uv.y));
  uv.y += u_distortion * center * cos(t + 2. * smoothstep(.0, 1., uv.x));

  uv.x += u_distortion * center * 0.5 * sin(t + .8 * smoothstep(.0, 1., uv.y)) * cos(.2 * t + 4.8 * smoothstep(.0, 1., uv.y));
  uv.y += u_distortion * center * 0.5 * cos(t + 4. * smoothstep(.0, 1., uv.x));

  // --- 旋涡 ---
  vec2 uvRotated = uv - vec2(.5);
  float angle = 3. * u_swirl * radius;
  uvRotated = rotate2d(uvRotated, -angle);
  uvRotated += vec2(.5);

  // --- 距离倒数加权颜色混合 ---
  vec3 color = vec3(0.);
  float opacity = 0.;
  float totalWeight = 0.;
  int cnt = int(u_colorsCount);

  for (int i = 0; i < 7; i++) {
    if (i < cnt) {
      vec2 pos = getPosition(i, t);
      vec4 col = getColor(i);
      vec3 colorFraction = col.rgb * col.a;
      float opacityFraction = col.a;

      float dist = length(uvRotated - pos);
      dist = pow(dist, 3.5);
      float weight = 1. / (dist + 1e-3);

      color += colorFraction * weight;
      opacity += opacityFraction * weight;
      totalWeight += weight;
    }
  }

  color /= max(1e-4, totalWeight);
  opacity /= max(1e-4, totalWeight);
  opacity = clamp(opacity, 0., 1.);

  // 与背景色混合（premultiplied alpha）
  vec3 bgColor = u_colorBack.rgb * u_colorBack.a;
  color = color + bgColor * (1.0 - opacity);
  opacity = opacity + u_colorBack.a * (1.0 - opacity);

  fragColor = vec4(color, opacity);
}
