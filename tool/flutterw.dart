import 'dart:convert';
import 'dart:io';

import '_workspace_cli.dart';

const _commandsRequiringAppPrep = {'run', 'build', 'drive'};
const _commandsRequiringTestPrep = {'test'};

Future<void> main(List<String> args) async {
  enterWorkspaceRoot();

  if (args.isEmpty) {
    stderr.writeln('用法: dart tool/flutterw.dart <flutter args...>');
    exit(64);
  }

  final command = _firstFlutterCommand(args);
  if (command != null && _commandsRequiringAppPrep.contains(command)) {
    await runOrExit(
      title: '执行项目预处理',
      executable: Platform.resolvedExecutable,
      arguments: const ['tool/project_prep.dart', 'app'],
    );
    await _runNativePrepIfNeeded(command, args);
  } else if (command != null && _commandsRequiringTestPrep.contains(command)) {
    await runOrExit(
      title: '执行测试预处理',
      executable: Platform.resolvedExecutable,
      arguments: const ['tool/project_prep.dart', 'test'],
    );
  }

  await runFlutterOrExit(
    title: '执行 flutter ${args.join(' ')}',
    arguments: args,
  );
}

Future<void> _runNativePrepIfNeeded(String command, List<String> args) async {
  final target = await _detectNativeTarget(command, args);
  if (target == null) {
    return;
  }

  final buildMode = _detectBuildMode(command, args);
  final nativeArgs = <String>[
    'tool/project_tasks.dart',
    'native:prepare',
    target.platform,
    buildMode,
  ];
  if (target.platform == 'android') {
    final targetPlatform =
        _extractOptionValue(args, '--target-platform', '--target-platform') ??
        target.androidTargetPlatform;
    if (targetPlatform != null && targetPlatform.isNotEmpty) {
      nativeArgs.add('--target-platform=$targetPlatform');
    }
  } else if (target.platform == 'macos') {
    final macOsArch = target.macOsArch;
    if (macOsArch != null && macOsArch.isNotEmpty) {
      nativeArgs.add('--arch=$macOsArch');
    }
  }
  await runOrExit(
    title: '准备 ${target.platform} 原生产物',
    executable: Platform.resolvedExecutable,
    arguments: nativeArgs,
  );
}

String? _firstFlutterCommand(List<String> args) {
  for (final arg in args) {
    if (!arg.startsWith('-')) {
      return arg;
    }
  }
  return null;
}

String? _macOsArchFromEnv() {
  final value = Platform.environment['FLUXDO_MACOS_ARCH']?.trim();
  return (value == null || value.isEmpty) ? null : value;
}

Future<_NativeTarget?> _detectNativeTarget(String command, List<String> args) async {
  switch (command) {
    case 'build':
      final buildTarget = _firstPositionalAfter(args, 'build');
      return switch (buildTarget) {
        'windows' => const _NativeTarget('windows'),
        'macos' => _NativeTarget('macos', macOsArch: _macOsArchFromEnv()),
        'linux' => const _NativeTarget('linux'),
        'ios' || 'ipa' => const _NativeTarget('ios'),
        'apk' || 'appbundle' || 'aar' => const _NativeTarget('android'),
        _ => null,
      };
    case 'run':
    case 'drive':
      final deviceId = _extractOptionValue(args, '-d', '--device-id');
      final directTarget = switch (deviceId) {
        'windows' => const _NativeTarget('windows'),
        'macos' => _NativeTarget('macos', macOsArch: _macOsArchFromEnv()),
        'linux' => const _NativeTarget('linux'),
        'android' => const _NativeTarget('android'),
        'ios' => const _NativeTarget('ios'),
        _ => null,
      };
      if (directTarget != null) {
        return directTarget;
      }

      final devices = await _loadFlutterDevices();
      final resolvedDevice = switch (deviceId) {
        null => devices.length == 1 ? devices.single : null,
        _ => devices.where((device) => device.id == deviceId).firstOrNull,
      };
      if (resolvedDevice == null) {
        return null;
      }
      return _nativeTargetFromDevice(resolvedDevice);
    default:
      return null;
  }
}

String _detectBuildMode(String command, List<String> args) {
  if (args.contains('--debug')) {
    return '--debug';
  }
  if (args.contains('--profile')) {
    return '--profile';
  }
  if (args.contains('--release')) {
    return '--release';
  }
  return command == 'run' ? '--debug' : '--release';
}

String? _firstPositionalAfter(List<String> args, String command) {
  final commandIndex = args.indexOf(command);
  if (commandIndex == -1) {
    return null;
  }

  for (var index = commandIndex + 1; index < args.length; index++) {
    final value = args[index];
    if (!value.startsWith('-')) {
      return value;
    }
  }
  return null;
}

String? _extractOptionValue(List<String> args, String shortOption, String longOption) {
  for (var index = 0; index < args.length; index++) {
    final value = args[index];
    if (value == shortOption || value == longOption) {
      if (index + 1 < args.length) {
        return args[index + 1];
      }
      return null;
    }
    if (value.startsWith('$longOption=')) {
      return value.substring(longOption.length + 1);
    }
  }
  return null;
}

Future<List<_FlutterDevice>> _loadFlutterDevices() async {
  try {
    final result = await Process.run(
      flutterExecutable,
      const ['devices', '--machine'],
      runInShell: Platform.isWindows,
      environment: await androidBuildEnvironment(),
      workingDirectory: workspaceRootPath,
    );
    if (result.exitCode != 0) {
      return const [];
    }

    final decoded = jsonDecode(result.stdout.toString());
    if (decoded is! List) {
      return const [];
    }

    return decoded
        .whereType<Map>()
        .map((item) => _FlutterDevice.fromJson(item.cast<String, dynamic>()))
        .whereType<_FlutterDevice>()
        .toList();
  } catch (_) {
    return const [];
  }
}

_NativeTarget? _nativeTargetFromDevice(_FlutterDevice device) {  final targetPlatform = device.targetPlatform;
  if (targetPlatform.startsWith('android')) {
    return _NativeTarget('android', androidTargetPlatform: targetPlatform);
  }
  if (targetPlatform == 'ios') {
    return const _NativeTarget('ios');
  }
  if (targetPlatform.startsWith('darwin')) {
    return _NativeTarget('macos', macOsArch: _macOsArchFromEnv());
  }
  if (targetPlatform.startsWith('windows')) {
    return const _NativeTarget('windows');
  }
  if (targetPlatform.startsWith('linux')) {
    return const _NativeTarget('linux');
  }
  return null;
}

class _NativeTarget {
  const _NativeTarget(this.platform, {this.androidTargetPlatform, this.macOsArch});

  final String platform;
  final String? androidTargetPlatform;
  final String? macOsArch;
}

class _FlutterDevice {
  const _FlutterDevice({
    required this.id,
    required this.targetPlatform,
  });

  final String id;
  final String targetPlatform;

  static _FlutterDevice? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim();
    final targetPlatform = json['targetPlatform']?.toString().trim();
    if (id == null || id.isEmpty || targetPlatform == null || targetPlatform.isEmpty) {
      return null;
    }
    return _FlutterDevice(id: id, targetPlatform: targetPlatform);
  }
}

extension on Iterable<_FlutterDevice> {
  _FlutterDevice? get firstOrNull => isEmpty ? null : first;
}
