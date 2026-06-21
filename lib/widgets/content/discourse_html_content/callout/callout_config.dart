import 'package:flutter/material.dart';

/// Callout 配置类
class CalloutConfig {
  final Color color;
  final IconData icon;
  final String defaultTitle;

  const CalloutConfig(this.color, this.icon, this.defaultTitle);
}

/// 获取 Callout 配置
CalloutConfig getCalloutConfig(String type) {
  switch (type) {
    case 'note':
      return CalloutConfig(Colors.blue, Icons.edit_note, 'Note');
    case 'abstract':
    case 'summary':
    case 'tldr':
      return CalloutConfig(Colors.cyan, Icons.subject, 'Summary');
    case 'info':
      return CalloutConfig(Colors.blue, Icons.info_outline, 'Info');
    case 'todo':
      return CalloutConfig(Colors.blue, Icons.check_circle_outline, 'Todo');
    case 'tip':
    case 'hint':
    case 'important':
      return CalloutConfig(Colors.teal, Icons.tips_and_updates, 'Tip');
    case 'success':
    case 'check':
    case 'done':
      return CalloutConfig(Colors.green, Icons.check_circle, 'Success');
    case 'question':
    case 'help':
    case 'faq':
      return CalloutConfig(Colors.orange, Icons.help_outline, 'Question');
    case 'warning':
    case 'caution':
    case 'attention':
      return CalloutConfig(Colors.orange, Icons.warning_amber, 'Warning');
    case 'failure':
    case 'fail':
    case 'missing':
      return CalloutConfig(Colors.red, Icons.close, 'Failure');
    case 'danger':
    case 'error':
      return CalloutConfig(Colors.red, Icons.dangerous, 'Danger');
    case 'bug':
      return CalloutConfig(Colors.red, Icons.bug_report, 'Bug');
    case 'example':
      return CalloutConfig(Colors.purple, Icons.list, 'Example');
    case 'quote':
    case 'cite':
      return CalloutConfig(Colors.grey, Icons.format_quote, 'Quote');
    default:
      // 未知类型使用灰色，标题首字母大写
      final defaultTitle = type.isNotEmpty
          ? type[0].toUpperCase() + type.substring(1)
          : 'Note';
      return CalloutConfig(Colors.grey, Icons.format_quote, defaultTitle);
  }
}

bool isKnownCalloutType(String type) {
  switch (type) {
    case 'note':
    case 'abstract':
    case 'summary':
    case 'tldr':
    case 'info':
    case 'todo':
    case 'tip':
    case 'hint':
    case 'important':
    case 'success':
    case 'check':
    case 'done':
    case 'question':
    case 'help':
    case 'faq':
    case 'warning':
    case 'caution':
    case 'attention':
    case 'failure':
    case 'fail':
    case 'missing':
    case 'danger':
    case 'error':
    case 'bug':
    case 'example':
    case 'quote':
    case 'cite':
      return true;
    default:
      return false;
  }
}
