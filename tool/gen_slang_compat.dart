import 'dart:convert';
import 'dart:io';

const _baseLocale = 'zh';
const _outputPath = 'lib/l10n/generated/app_localizations_compat.g.dart';

void main(List<String> args) {
  final checkOnly = args.contains('--check');
  final outputFile = File(_outputPath);
  final generated = _generateCompatSource();

  if (checkOnly) {
    if (!outputFile.existsSync()) {
      stderr.writeln('[ERROR] 缺少生成文件: $_outputPath');
      stderr.writeln('[FAILED] 请运行: dart tool/gen_l10n.dart');
      exit(1);
    }
    final current = outputFile.readAsStringSync();
    if (current != generated) {
      stderr.writeln('[ERROR] AppLocalizations 兼容层不是最新的');
      stderr.writeln('[FAILED] 请运行: dart tool/gen_l10n.dart');
      exit(1);
    }
    stdout.writeln('[OK] AppLocalizations 兼容层已是最新状态');
    return;
  }

  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(generated);
  stdout.writeln('[OK] 已生成 $_outputPath');
}

String _generateCompatSource() {
  final modulesDir = Directory('lib/l10n/modules');
  if (!modulesDir.existsSync()) {
    throw StateError('模块目录不存在: ${modulesDir.path}');
  }

  final modules =
      modulesDir
          .listSync()
          .whereType<Directory>()
          .map((dir) => dir.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .toList()
        ..sort();

  final buffer = StringBuffer();
  buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  buffer.writeln('// ignore_for_file: non_constant_identifier_names');
  buffer.writeln();
  buffer.writeln("part of '../app_localizations.dart';");
  buffer.writeln();
  buffer.writeln('extension AppLocalizationsCompat on Translations {');

  final seenKeys = <String, String>{};

  for (final module in modules) {
    final file = File('lib/l10n/modules/$module/${module}_$_baseLocale.arb');
    if (!file.existsSync()) {
      throw StateError('缺少基础语言文件: ${file.path}');
    }

    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final namespaceAccessor = _slangIdentifier(module);

    for (final entry in data.entries) {
      final key = entry.key;
      if (key == '@@locale' || key.startsWith('@')) {
        continue;
      }

      final previousModule = seenKeys[key];
      if (previousModule != null) {
        throw StateError('检测到重复 key: $key ($previousModule, $module)');
      }
      seenKeys[key] = module;

      final meta = data['@$key'];
      final placeholders = meta is Map<String, dynamic>
          ? (meta['placeholders'] as Map?)?.cast<String, dynamic>()
          : null;

      if (placeholders == null || placeholders.isEmpty) {
        final slangKey = _slangIdentifier(key);
        buffer.writeln();
        buffer.writeln('  String get $key => $namespaceAccessor.$slangKey;');
        continue;
      }

      final params = <String>[];
      final args = <String>[];
      placeholders.forEach((name, value) {
        final type = _normalizeType(
          value is Map<String, dynamic> ? value['type'] as String? : null,
        );
        params.add('$type $name');
        args.add(name);
      });

      final slangKey = _slangIdentifier(key);
      buffer.writeln();
      buffer.writeln('  String $key(${params.join(', ')}) {');
      final namedArgs = args.map((arg) => '$arg: $arg').join(', ');
      buffer.writeln('    return $namespaceAccessor.$slangKey($namedArgs);');
      buffer.writeln('  }');
    }
  }

  buffer.writeln('}');
  return buffer.toString();
}

String _normalizeType(String? type) {
  switch (type) {
    case 'int':
      return 'int';
    case 'double':
      return 'double';
    case 'num':
      return 'num';
    case 'bool':
      return 'bool';
    case 'DateTime':
      return 'DateTime';
    default:
      return 'String';
  }
}

String _slangIdentifier(String value) {
  return value
      .replaceAllMapped(
        RegExp(r'(?<!^)([A-Z])'),
        (match) => '_${match.group(1)}',
      )
      .toLowerCase();
}
