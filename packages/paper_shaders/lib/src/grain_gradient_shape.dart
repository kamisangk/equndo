/// GrainGradient 支持的形状类型
enum GrainGradientShape {
  wave(1.0),
  dots(2.0),
  truchet(3.0),
  corners(4.0),
  ripple(5.0),
  blob(6.0),
  sphere(7.0);

  const GrainGradientShape(this.value);

  /// 传递给 shader 的 float 值
  final double value;
}
