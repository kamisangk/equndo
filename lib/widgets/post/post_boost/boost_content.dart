import 'dart:collection';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../../models/topic.dart';
import '../../../utils/emoji_shortcodes.dart';

class ParsedBoostContent {
  final String displayText;
  final String groupingKey;

  const ParsedBoostContent({
    required this.displayText,
    required this.groupingKey,
  });
}

class BoostGroup {
  final String displayText;
  final String groupingKey;
  final List<Boost> boosts;

  const BoostGroup({
    required this.displayText,
    required this.groupingKey,
    required this.boosts,
  });

  int get count => boosts.length;
}

List<BoostGroup> groupBoostsByContent(List<Boost> boosts) {
  final grouped = <String, List<Boost>>{};
  final order = <String>[];

  for (final boost in boosts) {
    final parsed = BoostContentParser.parse(boost.cooked);
    final key = parsed.groupingKey;
    if (!grouped.containsKey(key)) {
      grouped[key] = <Boost>[];
      order.add(key);
    }
    grouped[key]!.add(boost);
  }

  return order.map((key) {
    final items = grouped[key]!;
    final parsed = BoostContentParser.parse(items.first.cooked);
    return BoostGroup(
      displayText: parsed.displayText,
      groupingKey: key,
      boosts: List<Boost>.unmodifiable(items),
    );
  }).toList(growable: false);
}

class BoostContentParser {
  static final LinkedHashMap<String, ParsedBoostContent> _cache =
      LinkedHashMap<String, ParsedBoostContent>();
  static const int _maxCacheEntries = 512;
  static const Set<String> _blockTags = {
    'p',
    'div',
    'li',
    'ul',
    'ol',
    'blockquote',
  };

  static ParsedBoostContent parse(String cooked) {
    final cached = _cache[cooked];
    if (cached != null) {
      return cached;
    }

    final parsed = _parse(cooked);
    _cache[cooked] = parsed;

    if (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }

    return parsed;
  }

  static ParsedBoostContent _parse(String cooked) {
    final fragment = html_parser.parseFragment(cooked);
    final writer = _BoostTextWriter();

    for (final node in fragment.nodes) {
      _appendNode(node, writer);
    }

    final displayText = writer.toDisplayText();
    final fallbackKey = cooked.replaceAll(RegExp(r'\s+'), ' ').trim();

    return ParsedBoostContent(
      displayText: displayText,
      groupingKey: displayText.isNotEmpty ? displayText : fallbackKey,
    );
  }

  static void _appendNode(dom.Node node, _BoostTextWriter writer) {
    if (node is dom.Text) {
      writer.write(node.text);
      return;
    }

    if (node is! dom.Element) {
      return;
    }

    final tag = node.localName ?? '';

    if (_blockTags.contains(tag)) {
      writer.writeSeparator();
    }

    if (tag == 'br') {
      writer.writeSeparator();
      return;
    }

    if (tag == 'img') {
      final classNames = (node.attributes['class'] ?? '')
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toSet();

      if (classNames.contains('emoji')) {
        final emojiName = _extractEmojiName(node);
        if (emojiName.isNotEmpty) {
          writer.write(':$emojiName:');
        }
        return;
      }
    }

    for (final child in node.nodes) {
      _appendNode(child, writer);
    }

    if (_blockTags.contains(tag)) {
      writer.writeSeparator();
    }
  }

  static String _extractEmojiName(dom.Element element) {
    final titledName = normalizeEmojiShortcodeName(
      element.attributes['title'] ?? element.attributes['alt'] ?? '',
    );
    if (titledName.isNotEmpty) {
      return titledName;
    }

    final src = element.attributes['src'] ?? '';
    final match = RegExp(
      r'/emoji/[^/]+/([^/?#]+?)(?:/(t\d))?\.png',
      caseSensitive: false,
    ).firstMatch(src);

    if (match == null) {
      return '';
    }

    final base = match.group(1);
    final tone = match.group(2);
    if (base == null || base.isEmpty) {
      return '';
    }

    return tone == null ? base : '$base:$tone';
  }
}

class _BoostTextWriter {
  final StringBuffer _buffer = StringBuffer();
  bool _endsWithWhitespace = false;

  void write(String text) {
    if (text.isEmpty) {
      return;
    }

    _buffer.write(text);
    _endsWithWhitespace = text.runes.isNotEmpty &&
        String.fromCharCode(text.runes.last).trim().isEmpty;
  }

  void writeSeparator() {
    if (_buffer.isEmpty || _endsWithWhitespace) {
      return;
    }

    _buffer.write(' ');
    _endsWithWhitespace = true;
  }

  String toDisplayText() {
    return _buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
