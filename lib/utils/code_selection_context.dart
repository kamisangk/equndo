class CodeSelectionContext {
  final String? language;

  const CodeSelectionContext({this.language});
}

class CodeSelectionContextTracker {
  CodeSelectionContextTracker._();

  static const String _payloadPrefix = '\u{E000}CODEQUOTE:';

  static final CodeSelectionContextTracker instance = CodeSelectionContextTracker._();

  CodeSelectionContext? _current;

  CodeSelectionContext? get current => _current;

  void set(CodeSelectionContext context) {
    _current = context;
  }

  void clear() {
    _current = null;
  }

  String toMarkdown(String selectedText, {CodeSelectionContext? context}) {
    final text = selectedText.replaceAll('\r\n', '\n');
    final language = context?.language?.trim() ?? _current?.language?.trim();
    final fence = language != null && language.isNotEmpty
        ? '```$language'
        : '```';
    return '$fence\n$text\n```';
  }

  String encodePayload(String selectedText, {CodeSelectionContext? context}) {
    final text = selectedText.replaceAll('\r\n', '\n');
    final language = context?.language?.trim() ?? _current?.language?.trim() ?? '';
    return '$_payloadPrefix$language\n$text';
  }

  ({String text, CodeSelectionContext context})? decodePayload(String value) {
    if (!value.startsWith(_payloadPrefix)) return null;

    final payload = value.substring(_payloadPrefix.length);
    final newlineIndex = payload.indexOf('\n');
    if (newlineIndex == -1) return null;

    final language = payload.substring(0, newlineIndex);
    final text = payload.substring(newlineIndex + 1);
    return (
      text: text,
      context: CodeSelectionContext(language: language.isEmpty ? null : language),
    );
  }
}
