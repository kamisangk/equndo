import 'package:flutter/widgets.dart';

import '../../../models/topic.dart';

/// 把当前 [Post] 广播给 HTML 子树的 InheritedWidget。
///
/// `flutter_widget_from_html` 在 cooked 未变化时会复用子树（比如 customWidgetBuilder
/// 返回的自定义组件实例），导致组件里 `widget.post` 无法感知外层 Post 对象的更新
/// （例如 like 点赞之外、不修改 cooked 的字段：policy_* 等）。
///
/// 通过 InheritedWidget 绕开这一限制：子组件用 `CurrentPostScope.of(context)`
/// 订阅当前 post；当外层 Post 对象引用变化时，Flutter 会直接通知所有依赖的
/// Element rebuild，不受中间 HtmlWidget 是否 diff 子树影响。
///
/// [updateShouldNotify] 用 `!identical` 判断：`_applyPostUpdate` 每次 refreshPost
/// 后都会 `copyWith` 产出新 Post 对象，引用必然不同，确保字段级（非 == 覆盖）变更
/// 也能触发通知。
class CurrentPostScope extends InheritedWidget {
  final Post post;

  const CurrentPostScope({
    super.key,
    required this.post,
    required super.child,
  });

  static Post? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CurrentPostScope>()
        ?.post;
  }

  @override
  bool updateShouldNotify(CurrentPostScope oldWidget) {
    return !identical(post, oldWidget.post);
  }
}
