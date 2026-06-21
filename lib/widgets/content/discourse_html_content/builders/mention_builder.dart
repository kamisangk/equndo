import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import '../../../../services/discourse_cache_manager.dart';
import '../../../../utils/link_launcher.dart';
import '../../../../utils/url_helper.dart';

/// 构建用户提及链接
Widget? buildMention({
  required BuildContext context,
  required ThemeData theme,
  required dynamic element,
  required double baseFontSize,
}) {
  final domElement = element as dom.Element;
  final href = domElement.attributes['href'];
  final isDark = theme.brightness == Brightness.dark;
  final fontSize = baseFontSize * 0.82;
  final emojiSize = fontSize * 1.2;

  // 提取文本（只包含文本节点，排除 img 标签）
  String mentionText = '';
  for (var node in domElement.nodes) {
    if (node.nodeType == dom.Node.TEXT_NODE) {
      mentionText += node.text ?? '';
    }
  }
  mentionText = mentionText.trim();

  // 查找状态 emoji 图片
  final emojiImgs = domElement.getElementsByTagName('img');
  dom.Element? statusEmoji;
  if (emojiImgs.isNotEmpty) {
    statusEmoji = emojiImgs.first;
  }

  return InlineCustomWidget(
    child: GestureDetector(
      onTap: href != null
          ? () => launchContentLink(context, href)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3a3d47) : const Color(0xFFe8ebef),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              mentionText,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: fontSize,
              ),
            ),
            if (statusEmoji != null) ...[
              const SizedBox(width: 2),
              _buildStatusEmoji(statusEmoji, emojiSize),
            ],
          ],
        ),
      ),
    ),
  );
}

/// 构建用户状态 emoji
Widget _buildStatusEmoji(dom.Element imgElement, double size) {
  final src = imgElement.attributes['src'] ?? '';
  if (src.isEmpty) return const SizedBox.shrink();

  // 将相对路径转换为绝对路径
  final resolvedSrc = UrlHelper.resolveUrlWithCdn(src);

  return Image(
    image: emojiImageProvider(resolvedSrc),
    width: size,
    height: size,
    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
  );
}
