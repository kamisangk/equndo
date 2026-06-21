import 'dart:io';

import 'package:dart_console/dart_console.dart';

final List<String> _scriptedPromptAnswers = _loadScriptedPromptAnswers();

class CliOption<T> {
  const CliOption({
    required this.value,
    required this.label,
    required this.detail,
    this.aliases = const <String>[],
  });

  final T value;
  final String label;
  final String detail;
  final List<String> aliases;
}

class CliUi {
  CliUi({Console? console}) : _console = console ?? Console();

  final Console _console;

  bool get canPrompt =>
      _scriptedPromptAnswers.isNotEmpty ||
      _stdinHasTerminal() ||
      _shellPromptSupported();

  bool get usesTui =>
      _scriptedPromptAnswers.isEmpty &&
      !_forcePlainUi() &&
      _stdinHasTerminal() &&
      _stdoutHasTerminal() &&
      !_isCiEnvironment() &&
      !_isDumbTerminal();

  Future<T?> select<T>({
    required String title,
    required List<CliOption<T>> options,
    int defaultIndex = 0,
  }) async {
    if (options.isEmpty) {
      return null;
    }

    if (_scriptedPromptAnswers.isNotEmpty) {
      _printPlainMenu(title, options);
      return _selectFromPrompt(
        title: title,
        options: options,
        defaultIndex: defaultIndex,
      );
    }

    if (usesTui) {
      return _selectWithTui(
        title: title,
        options: options,
        defaultIndex: defaultIndex,
      );
    }

    _printPlainMenu(title, options);
    return _selectFromPrompt(
      title: title,
      options: options,
      defaultIndex: defaultIndex,
    );
  }

  Future<String?> input({
    required String prompt,
    String? defaultValue,
    bool allowEmpty = false,
    String? Function(String value)? validator,
  }) async {
    while (true) {
      final promptText = defaultValue == null || defaultValue.isEmpty
          ? '$prompt: '
          : '$prompt [$defaultValue]: ';

      final raw = await _readLine(promptText, cancelOnEscape: true);
      if (raw == null) {
        return null;
      }

      final trimmed = raw.trim();
      final effectiveValue = trimmed.isEmpty ? (defaultValue ?? '') : trimmed;
      if (effectiveValue.isEmpty && !allowEmpty) {
        stdout.writeln('输入不能为空');
        continue;
      }

      final validationMessage = validator?.call(effectiveValue);
      if (validationMessage != null) {
        stdout.writeln(validationMessage);
        continue;
      }

      return effectiveValue;
    }
  }

  Future<bool?> confirm({
    required String prompt,
    bool defaultValue = false,
  }) async {
    if (usesTui) {
      return select<bool>(
        title: prompt,
        defaultIndex: defaultValue ? 0 : 1,
        options: const [
          CliOption<bool>(
            value: true,
            label: 'yes',
            detail: '继续执行',
            aliases: <String>['y'],
          ),
          CliOption<bool>(
            value: false,
            label: 'no',
            detail: '取消',
            aliases: <String>['n'],
          ),
        ],
      );
    }

    final suffix = defaultValue ? ' (Y/n) ' : ' (y/N) ';
    final reply = await _readLine('$prompt$suffix', cancelOnEscape: true);
    if (reply == null) {
      return null;
    }
    final normalized = reply.trim().toLowerCase();
    if (normalized.isEmpty) {
      return defaultValue;
    }
    if (normalized == 'y' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'n' || normalized == 'no') {
      return false;
    }
    stdout.writeln('请输入 y/yes 或 n/no。');
    return confirm(prompt: prompt, defaultValue: defaultValue);
  }

  void _printPlainMenu<T>(String title, List<CliOption<T>> options) {
    stdout.writeln(title);
    for (var index = 0; index < options.length; index++) {
      final option = options[index];
      stdout.writeln(
        '  ${index + 1}. ${option.label.padRight(10)} ${option.detail}',
      );
    }
  }

  Future<T?> _selectFromPrompt<T>({
    required String title,
    required List<CliOption<T>> options,
    required int defaultIndex,
  }) async {
    while (true) {
      final input = await _readLine(
        '输入序号或名称 [${defaultIndex + 1}]: ',
        cancelOnEscape: true,
      );
      if (input == null) {
        return null;
      }

      final raw = input.trim();
      if (_isCancelToken(raw)) {
        return null;
      }

      final selectedOption = _matchOption(raw, options, defaultIndex);
      if (selectedOption != null) {
        stdout.writeln('');
        return selectedOption.value;
      }

      stdout.writeln(
        '请输入 1-${options.length} 之间的序号，或 ${_labelsForOptions(options)}。',
      );
    }
  }

  Future<T?> _selectWithTui<T>({
    required String title,
    required List<CliOption<T>> options,
    required int defaultIndex,
  }) async {
    final start = _console.cursorPosition;
    if (start == null) {
      _printPlainMenu(title, options);
      return _selectFromPrompt(
        title: title,
        options: options,
        defaultIndex: defaultIndex,
      );
    }

    var selectedIndex = defaultIndex.clamp(0, options.length - 1);
    const helpText = '↑/↓ 选择  Enter 确认  数字/名称直达  q 取消';

    void render() {
      _console.cursorPosition = start;
      _renderMenuLine(title, titleLine: true);
      _renderMenuLine(helpText, helpLine: true);
      for (var index = 0; index < options.length; index++) {
        final option = options[index];
        final selected = index == selectedIndex;
        final prefix = selected ? '> ' : '  ';
        _renderMenuLine('$prefix${option.label.padRight(10)} ${option.detail}', selected: selected);
      }
    }

    _console.hideCursor();
    try {
      render();
      while (true) {
        final key = _console.readKey();

        if (!key.isControl) {
          final char = key.char.trim().toLowerCase();
          if (char.isEmpty) {
            continue;
          }
          if (_isCancelToken(char)) {
            return null;
          }

          final selectedByText = _matchOption(
            char,
            options,
            defaultIndex,
          );
          if (selectedByText != null) {
            selectedIndex = options.indexOf(selectedByText);
            render();
            return selectedByText.value;
          }
        }

        switch (key.controlChar) {
          case ControlCharacter.arrowUp:
          case ControlCharacter.arrowLeft:
            selectedIndex = (selectedIndex - 1 + options.length) % options.length;
            render();
          case ControlCharacter.arrowDown:
          case ControlCharacter.arrowRight:
            selectedIndex = (selectedIndex + 1) % options.length;
            render();
          case ControlCharacter.home:
            selectedIndex = 0;
            render();
          case ControlCharacter.end:
            selectedIndex = options.length - 1;
            render();
          case ControlCharacter.enter:
            return options[selectedIndex].value;
          case ControlCharacter.escape:
          case ControlCharacter.ctrlC:
            return null;
          default:
            break;
        }
      }
    } finally {
      _console.resetColorAttributes();
      _console.showCursor();
      _console.writeLine();
    }
  }

  void _renderMenuLine(
    String text, {
    bool selected = false,
    bool titleLine = false,
    bool helpLine = false,
  }) {
    _console.eraseLine();
    if (titleLine) {
      _console.setForegroundColor(ConsoleColor.brightWhite);
      _console.setTextStyle(bold: true);
    } else if (helpLine) {
      _console.setForegroundColor(ConsoleColor.brightBlack);
    } else if (selected) {
      _console.setForegroundColor(ConsoleColor.brightCyan);
      _console.setTextStyle(bold: true);
    }

    _console.write(text);
    _console.resetColorAttributes();
    _console.writeLine();
  }

  Future<String?> _readLine(
    String prompt, {
    bool cancelOnEscape = false,
  }) async {
    final scripted = _consumeScriptedPromptAnswer();
    if (scripted != null) {
      stdout.writeln('$prompt$scripted');
      return scripted;
    }

    if (usesTui) {
      _console.write(prompt);
      return _console.readLine(
        cancelOnBreak: true,
        cancelOnEscape: cancelOnEscape,
        cancelOnEOF: true,
      );
    }

    final directReply = _readLineFromStdin(prompt);
    if (directReply != null) {
      return directReply;
    }

    return _readLineViaShell(prompt);
  }
}

String? _readLineFromStdin(String prompt) {
  if (!_stdinHasTerminal()) {
    return null;
  }

  stdout.write(prompt);
  try {
    return stdin.readLineSync();
  } on StdinException {
    return null;
  }
}

Future<String?> _readLineViaShell(String prompt) async {
  File? replyFile;
  try {
    replyFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'fluxdo_cli_prompt_${pid}_${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    final environment = Map<String, String>.from(Platform.environment)
      ..['FLUXDO_CLI_PROMPT'] = prompt
      ..['FLUXDO_CLI_REPLY_FILE'] = replyFile.path;

    final executable = Platform.isWindows ? 'powershell' : 'sh';
    final arguments = Platform.isWindows
        ? const [
            '-NoLogo',
            '-NoProfile',
            '-Command',
            r"$reply = Read-Host $env:FLUXDO_CLI_PROMPT; if ($null -eq $reply) { exit 2 }; Set-Content -LiteralPath $env:FLUXDO_CLI_REPLY_FILE -NoNewline -Value $reply; exit 0",
          ]
        : [
            '-c',
            r'printf "%s" "$FLUXDO_CLI_PROMPT" > /dev/tty; '
                r'IFS= read -r reply < /dev/tty || exit 2; '
                r'printf "%s" "$reply" > "$FLUXDO_CLI_REPLY_FILE"',
          ];

    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
      environment: environment,
    );
    final exitCode = await process.exitCode;
    if (exitCode != 0 || !replyFile.existsSync()) {
      return null;
    }

    return replyFile.readAsStringSync();
  } on ProcessException {
    return null;
  } on FileSystemException {
    return null;
  } finally {
    try {
      replyFile?.deleteSync();
    } on FileSystemException {
      // ignore cleanup failure
    }
  }
}

CliOption<T>? _matchOption<T>(
  String raw,
  List<CliOption<T>> options,
  int defaultIndex,
) {
  if (raw.isEmpty) {
    return options[defaultIndex];
  }

  final asIndex = int.tryParse(raw);
  if (asIndex != null && asIndex >= 1 && asIndex <= options.length) {
    return options[asIndex - 1];
  }

  final normalized = raw.trim().toLowerCase();
  for (final option in options) {
    if (normalized == option.label.toLowerCase()) {
      return option;
    }
    if (option.aliases.any((alias) => normalized == alias.toLowerCase())) {
      return option;
    }
  }

  return null;
}

String _labelsForOptions<T>(List<CliOption<T>> options) {
  return options.map((option) => option.label).join(' / ');
}

bool _isCancelToken(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'q' || normalized == 'quit' || normalized == 'exit';
}

bool _stdinHasTerminal() {
  try {
    return stdin.hasTerminal;
  } on StdinException {
    return false;
  }
}

bool _stdoutHasTerminal() {
  try {
    return stdout.hasTerminal;
  } on StdoutException {
    return false;
  }
}

bool _shellPromptSupported() =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

bool _isCiEnvironment() {
  final ci = Platform.environment['CI']?.trim().toLowerCase();
  return ci == '1' || ci == 'true';
}

bool _isDumbTerminal() =>
    Platform.environment['TERM']?.trim().toLowerCase() == 'dumb';

bool _forcePlainUi() {
  final value = Platform.environment['FLUXDO_CLI_FORCE_PLAIN']?.trim().toLowerCase();
  return value == '1' || value == 'true' || value == 'yes';
}

List<String> _loadScriptedPromptAnswers() {
  final raw =
      Platform.environment['FLUXDO_CLI_TEST_INPUTS']?.trim() ??
      Platform.environment['FLUXDO_RELEASE_TEST_INPUTS']?.trim();
  if (raw == null || raw.isEmpty) {
    return <String>[];
  }
  return raw.split('|').map((item) => item.trim()).toList();
}

String? _consumeScriptedPromptAnswer() {
  if (_scriptedPromptAnswers.isEmpty) {
    return null;
  }
  return _scriptedPromptAnswers.removeAt(0);
}
