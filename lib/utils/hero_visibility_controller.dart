import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 控制哪个 Hero tag 对应的图片应该在底层页面隐藏
/// 用于解决 opaque: false 路由中 Hero 切换不更新的问题
class HeroVisibilityController extends ChangeNotifier {
  HeroVisibilityController._();
  static final HeroVisibilityController instance = HeroVisibilityController._();

  String? _hiddenHeroTag;
  bool _isPopping = false;
  bool _notifyScheduled = false;

  /// 当前应该隐藏的 hero tag
  String? get hiddenHeroTag => _hiddenHeroTag;

  /// 是否正在 pop 飞行结束
  bool get isPopping => _isPopping;

  /// 设置当前应该隐藏的 hero tag（静默版，不触发通知）
  /// 用于 initState 中初始化，避免构建期间触发 rebuild
  void setHiddenTagSilent(String? tag) {
    _hiddenHeroTag = tag;
    _isPopping = false;
  }

  /// 设置当前应该隐藏的 hero tag（带通知）
  void setHiddenTag(String? tag) {
    if (_hiddenHeroTag == tag && !_isPopping) return;
    _hiddenHeroTag = tag;
    _isPopping = false;
    _safeNotify();
  }

  /// Pop 飞行结束时调用
  /// 从动画状态监听器调用，在 handleBeginFrame 阶段（build 之前），
  /// 直接通知以确保同帧内 rebuild，避免闪烁
  void startPopping() {
    if (_isPopping) return;
    _isPopping = true;
    notifyListeners();
  }

  /// 清除所有状态（dispose 时调用）
  void clear() {
    _hiddenHeroTag = null;
    _isPopping = false;
    // dispose 时不通知，避免 widget tree 锁定
  }

  /// 统一延迟到帧结束后通知，避免在 build/dispose/动画期间触发 rebuild
  void _safeNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}
