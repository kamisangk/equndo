class _PlaceholderReplacer {
  _PlaceholderReplacer(this._placeholder, this._startDelimiter, this._endDelimiter) {
    _pattern = RegExp(
      '${RegExp.escape(_startDelimiter)}$_placeholder(\\d+)${RegExp.escape(_endDelimiter)}',
    );
  }

  final String _placeholder;
  final String _startDelimiter;
  final String _endDelimiter;
  late final RegExp _pattern;
  final List<String> _items = <String>[];
  int _index = 0;

  String store(String item) {
    if (_items.length <= _index) {
      _items.add(item);
    } else {
      _items[_index] = item;
    }
    return '$_startDelimiter$_placeholder${_index++}$_endDelimiter';
  }

  String restore(String text) {
    return text.replaceAllMapped(_pattern, (match) {
      final index = int.tryParse(match.group(1) ?? '') ?? -1;
      if (index >= 0 && index < _items.length) {
        return _items[index];
      }
      return '';
    });
  }

  void reset() {
    _items.clear();
    _index = 0;
  }
}

/// Pangu - 中英文混排优化
///
/// 参考 pangu.js 行为，修复中英文/数字/标点的间距问题。
/// 同时保护 Markdown/Emoji/HTML 相关结构，避免破坏内容。
class Pangu {
  Pangu();

  final String version = '8.0.0';

  static const String _cjk =
      '\u2e80-\u2eff\u2f00-\u2fdf\u3040-\u309f\u30a0-\u30fa\u30fc-\u30ff\u3100-\u312f\u3200-\u32ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff';
  static const String _an = 'A-Za-z0-9';
  static const String _a = 'A-Za-z';
  static const String _upperAn = 'A-Z0-9';

  static const String _operatorsBase = '\\+\\*=&';
  static const String _operatorsWithHyphen = '$_operatorsBase\\-';
  static const String _operatorsNoHyphen = _operatorsBase;
  static const String _gradeOperators = '\\+\\-\\*';

  static const String _quotes = '`"\u05f4';

  static const String _leftBracketsBasic = '\\(\\[\\{';
  static const String _rightBracketsBasic = '\\)\\]\\}';
  static const String _leftBracketsExtended = '\\(\\[\\{<>\u201c';
  static const String _rightBracketsExtended = '\\)\\]\\}<>\u201d';

  static const String _ansCjkAfter =
      '$_a\u0370-\u03ff0-9@\\\$%\\^&\\*\\-\\+\\\\=\u00a1-\u00ff\u2150-\u218f\u2700—\u27bf';
  static const String _ansBeforeCjk =
      '$_a\u0370-\u03ff0-9\\\$%\\^&\\*\\-\\+\\\\=\u00a1-\u00ff\u2150-\u218f\u2700—\u27bf';

  static const String _filePathDirs =
      'home|root|usr|etc|var|opt|tmp|dev|mnt|proc|sys|bin|boot|lib|media|run|sbin|srv|node_modules|path|project|src|dist|test|tests|docs|templates|assets|public|static|config|scripts|tools|build|out|target|your|\\.claude|\\.git|\\.vscode';
  static const String _filePathChars = '[A-Za-z0-9_\\-\\.@\\+\\*]+';

  static final RegExp _unixAbsoluteFilePath = RegExp(
    '/(?:\\.?(?:$_filePathDirs)|\\.(?:[A-Za-z0-9_\\-]+))(?:/$_filePathChars)*',
  );
  static final RegExp _unixRelativeFilePath = RegExp(
    '(?:\\./)?(?:$_filePathDirs)(?:/$_filePathChars)+',
  );
  static final RegExp _windowsFilePath = RegExp(
    '[A-Z]:\\\\(?:[A-Za-z0-9_\\-\\. ]+\\\\?)+',
  );

  static final RegExp _anyCjk = RegExp('[$_cjk]');

  static final RegExp _cjkPunctuation =
      RegExp('([$_cjk])([!;,\\?:]+)(?=[$_cjk$_an])');
  static final RegExp _anPunctuationCjk =
      RegExp('([$_an])([!;,\\?]+)([$_cjk])');
  static final RegExp _cjkTilde =
      RegExp('([$_cjk])(~+)(?!=)(?=[$_cjk$_an])');
  static final RegExp _cjkTildeEquals = RegExp('([$_cjk])(~=)');
  static final RegExp _cjkPeriod =
      RegExp('([$_cjk])(\\.)(?![$_an\\./])(?=[$_cjk$_an])');
  static final RegExp _anPeriodCjk =
      RegExp('([$_an])(\\.)([$_cjk])');
  static final RegExp _anColonCjk = RegExp('([$_an])(:)([$_cjk])');
  static final RegExp _dotsCjk = RegExp('([\\.]{2,}|\u2026)([$_cjk])');
  static final RegExp _fixCjkColonAns =
      RegExp('([$_cjk])\\:([$_upperAn\\(\\)])');

  static final RegExp _cjkQuote = RegExp('([$_cjk])([$_quotes])');
  static final RegExp _quoteCjk = RegExp('([$_quotes])([$_cjk])');
  static final RegExp _fixQuoteAnyQuote =
      RegExp('([$_quotes]+)[ ]*(.+?)[ ]*([$_quotes]+)');
  static final RegExp _quoteAn = RegExp('([\u201d])([$_an])');
  static final RegExp _cjkQuoteAn = RegExp('([$_cjk])(")([$_an])');

  static final RegExp _cjkSingleQuoteButPossessive =
      RegExp("([$_cjk])('[^s])");
  static final RegExp _singleQuoteCjk = RegExp("(')([$_cjk])");
  static final RegExp _fixPossessiveSingleQuote =
      RegExp("([$_an$_cjk])( )('s)");

  static final RegExp _hashAnsCjkHash =
      RegExp('([$_cjk])(#)([$_cjk]+)(#)([$_cjk])');
  static final RegExp _cjkHash = RegExp('([$_cjk])(#([^ ]))');
  static final RegExp _hashCjk = RegExp('(([^ ])#)([$_cjk])');

  static final RegExp _cjkOperatorAns =
      RegExp('([$_cjk])([$_operatorsWithHyphen])([$_an])');
  static final RegExp _ansOperatorCjk =
      RegExp('([$_an])([$_operatorsWithHyphen])([$_cjk])');
  static final RegExp _ansOperatorAns =
      RegExp('([$_an])([$_operatorsNoHyphen])([$_an])');

  static final RegExp _ansHyphenAnsNotCompound = RegExp(
    '([A-Za-z])(-(?![a-z]))([A-Za-z0-9])|([A-Za-z]+[0-9]+)(-(?![a-z]))([0-9])|([0-9])(-(?![a-z0-9]))([A-Za-z])',
  );

  static final RegExp _cjkSlashCjk = RegExp('([$_cjk])([/])([$_cjk])');
  static final RegExp _cjkSlashAns = RegExp('([$_cjk])([/])([$_an])');
  static final RegExp _ansSlashCjk = RegExp('([$_an])([/])([$_cjk])');
  static final RegExp _ansSlashAns = RegExp('([$_an])([/])([$_an])');

  static final RegExp _singleLetterGradeCjk =
      RegExp('\\b([$_a])([$_gradeOperators])([$_cjk])');

  static final RegExp _cjkLessThan = RegExp('([$_cjk])(<)([$_an])');
  static final RegExp _lessThanCjk = RegExp('([$_an])(<)([$_cjk])');
  static final RegExp _cjkGreaterThan = RegExp('([$_cjk])(>)([$_an])');
  static final RegExp _greaterThanCjk = RegExp('([$_an])(>)([$_cjk])');
  static final RegExp _ansLessThanAns = RegExp('([$_an])(<)([$_an])');
  static final RegExp _ansGreaterThanAns = RegExp('([$_an])(>)([$_an])');

  static final RegExp _cjkLeftBracket =
      RegExp('([$_cjk])([$_leftBracketsExtended])');
  static final RegExp _rightBracketCjk =
      RegExp('([$_rightBracketsExtended])([$_cjk])');
  static final RegExp _ansCjkLeftBracketAnyRightBracket = RegExp(
    '([$_an$_cjk])[ ]*([\u201c])([$_an$_cjk\\-_ ]+)([\u201d])',
  );
  static final RegExp _leftBracketAnyRightBracketAnsCjk = RegExp(
    '([\u201c])([$_an$_cjk\\-_ ]+)([\u201d])[ ]*([$_an$_cjk])',
  );

  static final RegExp _rightBracketAn =
      RegExp('([$_rightBracketsBasic])([$_an])');
  static final RegExp _anLeftBracket =
      RegExp('([$_an])([$_leftBracketsBasic])');
  static final RegExp _anCharsOnly = RegExp('^[$_an]*\$');

  static final RegExp _cjkUnixAbsoluteFilePath = RegExp(
    '([$_cjk])(${_unixAbsoluteFilePath.pattern})',
  );
  static final RegExp _cjkUnixRelativeFilePath = RegExp(
    '([$_cjk])(${_unixRelativeFilePath.pattern})',
  );
  static final RegExp _cjkWindowsPath = RegExp(
    '([$_cjk])(${_windowsFilePath.pattern})',
  );

  static final RegExp _unixAbsoluteFilePathSlashCjk = RegExp(
    '(${_unixAbsoluteFilePath.pattern}/)([$_cjk])',
  );
  static final RegExp _unixRelativeFilePathSlashCjk = RegExp(
    '(${_unixRelativeFilePath.pattern}/)([$_cjk])',
  );

  static final RegExp _cjkAns = RegExp('([$_cjk])([$_ansCjkAfter])');
  static final RegExp _ansCjk = RegExp('([$_ansBeforeCjk])([$_cjk])');

  static final RegExp _sA = RegExp('(%)([$_a])');
  static final RegExp _middleDot = RegExp('([ ]*)([\u00b7\u2022\u2027])([ ]*)');

  String _replaceWithGroups(String input, RegExp pattern, String replacement) {
    return input.replaceAllMapped(pattern, (match) {
      return replacement.replaceAllMapped(RegExp(r'\$(\d+)'), (groupMatch) {
        final index = int.tryParse(groupMatch.group(1) ?? '') ?? 0;
        return match.group(index) ?? '';
      });
    });
  }

  String spacingText(String text) {
    if (text.length <= 1 || !_anyCjk.hasMatch(text)) {
      return text;
    }

    var newText = text;

    // 保护 Markdown 围栏代码块
    final fenceCodeManager = _PlaceholderReplacer('FENCE_CODE_', '\uE006', '\uE007');
    newText = newText.replaceAllMapped(RegExp('```[\\s\\S]*?```'), (match) {
      return fenceCodeManager.store(match.group(0) ?? '');
    });
    newText = newText.replaceAllMapped(RegExp('~~~[\\s\\S]*?~~~'), (match) {
      return fenceCodeManager.store(match.group(0) ?? '');
    });

    // 保护 HTML 代码块/样式/脚本
    final htmlBlockManager = _PlaceholderReplacer('HTML_BLOCK_', '\uE012', '\uE013');
    newText = newText.replaceAllMapped(
      RegExp('<pre\\b[^>]*>[\\s\\S]*?<\\/pre>', caseSensitive: false),
      (match) => htmlBlockManager.store(match.group(0) ?? ''),
    );
    newText = newText.replaceAllMapped(
      RegExp('<code\\b[^>]*>[\\s\\S]*?<\\/code>', caseSensitive: false),
      (match) => htmlBlockManager.store(match.group(0) ?? ''),
    );
    newText = newText.replaceAllMapped(
      RegExp('<script\\b[^>]*>[\\s\\S]*?<\\/script>', caseSensitive: false),
      (match) => htmlBlockManager.store(match.group(0) ?? ''),
    );
    newText = newText.replaceAllMapped(
      RegExp('<style\\b[^>]*>[\\s\\S]*?<\\/style>', caseSensitive: false),
      (match) => htmlBlockManager.store(match.group(0) ?? ''),
    );

    // 保护行内代码
    final backtickManager =
        _PlaceholderReplacer('BACKTICK_CONTENT_', '\uE004', '\uE005');
    newText = newText.replaceAllMapped(RegExp('`([^`]+)`'), (match) {
      final content = match.group(1) ?? '';
      return '`${backtickManager.store(content)}`';
    });

    // 保护 Markdown 链接/图片
    final markdownLinkManager = _PlaceholderReplacer('MD_LINK_', '\uE008', '\uE009');
    newText = newText.replaceAllMapped(
      RegExp('!?\\[[^\\]]*\\]\\([^\\)\\s]+(?:\\s+[^\\)]*)?\\)'),
      (match) => markdownLinkManager.store(match.group(0) ?? ''),
    );

    // 保护自动链接（<http://...>）
    final autoLinkManager = _PlaceholderReplacer('AUTO_LINK_', '\uE00A', '\uE00B');
    newText = newText.replaceAllMapped(RegExp('<https?://[^>]+>'), (match) {
      return autoLinkManager.store(match.group(0) ?? '');
    });

    // 保护 Emoji（:smile:）
    final emojiManager = _PlaceholderReplacer('EMOJI_', '\uE00C', '\uE00D');
    newText = newText.replaceAllMapped(RegExp(':[A-Za-z0-9_+\\-]+:'), (match) {
      return emojiManager.store(match.group(0) ?? '');
    });

    // 保护 HTML 实体
    final entityManager = _PlaceholderReplacer('HTML_ENTITY_', '\uE00E', '\uE00F');
    newText = newText.replaceAllMapped(RegExp('&[A-Za-z0-9#]+;'), (match) {
      return entityManager.store(match.group(0) ?? '');
    });

    // 保护 Markdown 粗体/斜体/删除线标记
    final mdFormattingManager =
        _PlaceholderReplacer('MD_FMT_', '\uE014', '\uE015');
    // ***bold italic*** (三星号，最先匹配)
    newText = newText.replaceAllMapped(
      RegExp(r'\*{3}(?!\s)(.+?)(?<!\s)\*{3}'),
      (match) => mdFormattingManager.store(match.group(0) ?? ''),
    );
    // **bold** (双星号)
    newText = newText.replaceAllMapped(
      RegExp(r'\*{2}(?!\s)(.+?)(?<!\s)\*{2}'),
      (match) => mdFormattingManager.store(match.group(0) ?? ''),
    );
    // *italic* (单星号，排除 word 字符相邻的乘号场景)
    newText = newText.replaceAllMapped(
      RegExp(r'(?<![*\w])\*(?!\s)(.+?)(?<!\s)\*(?![*\w])'),
      (match) => mdFormattingManager.store(match.group(0) ?? ''),
    );
    // ~~strikethrough~~ (删除线)
    newText = newText.replaceAllMapped(
      RegExp(r'~~(?!\s)(.+?)(?<!\s)~~'),
      (match) => mdFormattingManager.store(match.group(0) ?? ''),
    );

    // 保护 BBCode 标签 ([b], [/b], [color=red], [url="..."] 等)
    final bbcodeTagManager =
        _PlaceholderReplacer('BBCODE_TAG_', '\uE016', '\uE017');
    var hasBbcodeTags = false;
    if (newText.contains('[')) {
      final bbcodePattern = RegExp(r'\[/?[a-zA-Z][a-zA-Z0-9]*(?:=[^\]]*)?]');
      if (bbcodePattern.hasMatch(newText)) {
        hasBbcodeTags = true;
        newText = newText.replaceAllMapped(bbcodePattern, (match) {
          return bbcodeTagManager.store(match.group(0) ?? '');
        });
      }
    }

    final htmlTagManager =
        _PlaceholderReplacer('HTML_TAG_PLACEHOLDER_', '\uE000', '\uE001');
    var hasHtmlTags = false;

    if (newText.contains('<')) {
      hasHtmlTags = true;
      final htmlTagPattern =
          RegExp('</?[a-zA-Z][a-zA-Z0-9]*(?:\\s+[^>]*)?>');

      newText = newText.replaceAllMapped(htmlTagPattern, (match) {
        return htmlTagManager.store(match.group(0) ?? '');
      });
    }

    newText = _replaceWithGroups(newText, _dotsCjk, r'$1 $2');

    newText = _replaceWithGroups(newText, _cjkPunctuation, r'$1$2 ');
    newText = _replaceWithGroups(newText, _anPunctuationCjk, r'$1$2 $3');
    newText = _replaceWithGroups(newText, _cjkTilde, r'$1$2 ');
    newText = _replaceWithGroups(newText, _cjkTildeEquals, r'$1 $2 ');
    newText = _replaceWithGroups(newText, _cjkPeriod, r'$1$2 ');
    newText = _replaceWithGroups(newText, _anPeriodCjk, r'$1$2 $3');
    newText = _replaceWithGroups(newText, _anColonCjk, r'$1$2 $3');
    newText = newText.replaceAllMapped(_fixCjkColonAns, (match) {
      return '${match.group(1)}\uFF1A${match.group(2)}';
    });

    newText = _replaceWithGroups(newText, _cjkQuote, r'$1 $2');
    newText = _replaceWithGroups(newText, _quoteCjk, r'$1 $2');
    newText = _replaceWithGroups(newText, _fixQuoteAnyQuote, r'$1$2$3');

    newText = _replaceWithGroups(newText, _quoteAn, r'$1 $2');
    newText = _replaceWithGroups(newText, _cjkQuoteAn, r'$1$2 $3');

    newText = _replaceWithGroups(newText, _fixPossessiveSingleQuote, r"$1's");

    final singleQuoteCjkManager =
        _PlaceholderReplacer('SINGLE_QUOTE_CJK_PLACEHOLDER_', '\uE030', '\uE031');
    final singleQuotePureCjk = RegExp('(\')([$_cjk]+)(\')');
    newText = newText.replaceAllMapped(singleQuotePureCjk, (match) {
      return singleQuoteCjkManager.store(match.group(0) ?? '');
    });

    newText = _replaceWithGroups(newText, _cjkSingleQuoteButPossessive, r'$1 $2');
    newText = _replaceWithGroups(newText, _singleQuoteCjk, r'$1 $2');

    newText = singleQuoteCjkManager.restore(newText);

    final textLength = newText.length;
    final slashCount = RegExp('/').allMatches(newText).length;

    if (slashCount <= 1) {
      if (textLength >= 5) {
        newText = _replaceWithGroups(newText, _hashAnsCjkHash, r'$1 $2$3$4 $5');
      }
      newText = _replaceWithGroups(newText, _cjkHash, r'$1 $2');
      newText = _replaceWithGroups(newText, _hashCjk, r'$1 $3');
    } else {
      if (textLength >= 5) {
        newText = _replaceWithGroups(newText, _hashAnsCjkHash, r'$1 $2$3$4 $5');
      }
      newText = _replaceWithGroups(
        newText,
        RegExp('([^/])([$_cjk])(#[A-Za-z0-9]+)\$'),
        r'$1$2 $3',
      );
    }

    final compoundWordManager = _PlaceholderReplacer(
      'COMPOUND_WORD_PLACEHOLDER_',
      '\uE010',
      '\uE011',
    );
    final compoundWordPattern = RegExp(
      '\\b(?:[A-Za-z0-9]*[a-z][A-Za-z0-9]*-[A-Za-z0-9]+|[A-Za-z0-9]+-[A-Za-z0-9]*[a-z][A-Za-z0-9]*|[A-Za-z]+-[0-9]+|[A-Za-z]+[0-9]+-[A-Za-z0-9]+)(?:-[A-Za-z0-9]+)*\\b',
    );
    newText = newText.replaceAllMapped(compoundWordPattern, (match) {
      return compoundWordManager.store(match.group(0) ?? '');
    });

    newText = _replaceWithGroups(newText, _singleLetterGradeCjk, r'$1$2 $3');

    newText = _replaceWithGroups(newText, _cjkOperatorAns, r'$1 $2 $3');
    newText = _replaceWithGroups(newText, _ansOperatorCjk, r'$1 $2 $3');
    newText = _replaceWithGroups(newText, _ansOperatorAns, r'$1 $2 $3');

    newText = newText.replaceAllMapped(_ansHyphenAnsNotCompound, (match) {
      if (match.group(1) != null && match.group(2) != null && match.group(3) != null) {
        return '${match.group(1)} ${match.group(2)} ${match.group(3)}';
      }
      if (match.group(4) != null && match.group(5) != null && match.group(6) != null) {
        return '${match.group(4)} ${match.group(5)} ${match.group(6)}';
      }
      if (match.group(7) != null && match.group(8) != null && match.group(9) != null) {
        return '${match.group(7)} ${match.group(8)} ${match.group(9)}';
      }
      return match.group(0) ?? '';
    });

    newText = _replaceWithGroups(newText, _cjkLessThan, r'$1 $2 $3');
    newText = _replaceWithGroups(newText, _lessThanCjk, r'$1 $2 $3');
    newText = _replaceWithGroups(newText, _ansLessThanAns, r'$1 $2 $3');
    newText = _replaceWithGroups(newText, _cjkGreaterThan, r'$1 $2 $3');
    newText = _replaceWithGroups(newText, _greaterThanCjk, r'$1 $2 $3');
    newText = _replaceWithGroups(newText, _ansGreaterThanAns, r'$1 $2 $3');

    newText = _replaceWithGroups(newText, _cjkUnixAbsoluteFilePath, r'$1 $2');
    newText = _replaceWithGroups(newText, _cjkUnixRelativeFilePath, r'$1 $2');
    newText = _replaceWithGroups(newText, _cjkWindowsPath, r'$1 $2');

    newText = _replaceWithGroups(newText, _unixAbsoluteFilePathSlashCjk, r'$1 $2');
    newText = _replaceWithGroups(newText, _unixRelativeFilePathSlashCjk, r'$1 $2');

    if (slashCount == 1) {
      final filePathManager =
          _PlaceholderReplacer('FILE_PATH_PLACEHOLDER_', '\uE020', '\uE021');
      final allFilePathPattern = RegExp(
        '(${_unixAbsoluteFilePath.pattern}|${_unixRelativeFilePath.pattern})',
      );
      newText = newText.replaceAllMapped(allFilePathPattern, (match) {
        return filePathManager.store(match.group(0) ?? '');
      });

      newText = _replaceWithGroups(newText, _cjkSlashCjk, r'$1 $2 $3');
      newText = _replaceWithGroups(newText, _cjkSlashAns, r'$1 $2 $3');
      newText = _replaceWithGroups(newText, _ansSlashCjk, r'$1 $2 $3');
      newText = _replaceWithGroups(newText, _ansSlashAns, r'$1 $2 $3');

      newText = filePathManager.restore(newText);
    }

    newText = compoundWordManager.restore(newText);

    newText = _replaceWithGroups(newText, _cjkLeftBracket, r'$1 $2');
    newText = _replaceWithGroups(newText, _rightBracketCjk, r'$1 $2');
    newText = _replaceWithGroups(newText, _ansCjkLeftBracketAnyRightBracket, r'$1 $2$3$4');
    newText = _replaceWithGroups(newText, _leftBracketAnyRightBracketAnsCjk, r'$1$2$3 $4');

    newText = _replaceAnLeftBracket(newText);
    newText = _replaceWithGroups(newText, _rightBracketAn, r'$1 $2');

    newText = _replaceWithGroups(newText, _cjkAns, r'$1 $2');
    newText = _replaceWithGroups(newText, _ansCjk, r'$1 $2');

    newText = _replaceWithGroups(newText, _sA, r'$1 $2');
    newText = newText.replaceAll(_middleDot, '\u30FB');

    newText = _fixBracketSpacing(newText);

    if (hasHtmlTags) {
      newText = htmlTagManager.restore(newText);
    }

    if (hasBbcodeTags) {
      newText = bbcodeTagManager.restore(newText);
    }

    newText = mdFormattingManager.restore(newText);
    newText = entityManager.restore(newText);
    newText = emojiManager.restore(newText);
    newText = autoLinkManager.restore(newText);
    newText = markdownLinkManager.restore(newText);
    newText = backtickManager.restore(newText);
    newText = htmlBlockManager.restore(newText);
    newText = fenceCodeManager.restore(newText);

    return newText;
  }

  bool hasProperSpacing(String text) {
    return spacingText(text) == text;
  }

  String _replaceAnLeftBracket(String text) {
    return text.replaceAllMapped(_anLeftBracket, (match) {
      final leading = match.group(1) ?? '';
      final bracket = match.group(2) ?? '';
      final bracketIndex = match.start + leading.length;
      if (bracketIndex > 0) {
        final prefix = text.substring(0, bracketIndex);
        final dotIndex = prefix.lastIndexOf('.');
        if (dotIndex != -1) {
          final afterDot = prefix.substring(dotIndex + 1);
          if (_anCharsOnly.hasMatch(afterDot)) {
            return '$leading$bracket';
          }
        }
      }
      return '$leading $bracket';
    });
  }

  String _fixBracketSpacing(String text) {
    final patterns = <Map<String, String>>[
      {'open': '<', 'close': '>', 'pattern': '<([^<>]*)>'},
      {'open': '(', 'close': ')', 'pattern': '\\(([^()]*)\\)'},
      {'open': '[', 'close': ']', 'pattern': '\\[([^\\[\\]]*)\\]'},
      {'open': '{', 'close': '}', 'pattern': '\\{([^{}]*)\\}'},
    ];

    var result = text;
    for (final item in patterns) {
      final pattern = RegExp(item['pattern'] ?? '');
      final open = item['open'] ?? '';
      final close = item['close'] ?? '';
      result = result.replaceAllMapped(pattern, (match) {
        final inner = match.group(1) ?? '';
        if (inner.isEmpty) {
          return '$open$close';
        }
        final trimmed = inner.replaceAll(RegExp(r'^ +| +$'), '');
        return '$open$trimmed$close';
      });
    }

    return result;
  }
}

final Pangu pangu = Pangu();

final RegExp anyCjk = Pangu._anyCjk;
