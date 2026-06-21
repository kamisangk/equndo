import 'dart:io';

String get workspaceRootPath => _workspaceRootPath;

String get flutterExecutable =>
    _readNonBlankEnv('FLUTTER_BIN') ??
    _resolveFlutterExecutableFromHome(_readNonBlankEnv('FLUXDO_FLUTTER_HOME')) ??
    _resolveFlutterExecutableFromHome(_readNonBlankEnv('FLUTTER_ROOT')) ??
    _resolveFlutterExecutableFromHome(_flutterHomeFromDartExecutable()) ??
    _resolveFlutterExecutableFromHome(_flutterHomeFromIdeaDartSdk()) ??
    (Platform.isWindows ? 'flutter.bat' : 'flutter');

String get toolingStampPath =>
    '.dart_tool${Platform.pathSeparator}fluxdo_tooling${Platform.pathSeparator}pubspec.stamp';

final String _workspaceRootPath = _resolveWorkspaceRootPath();

void enterWorkspaceRoot() {
  if (_normalizePath(Directory.current.path) == _normalizePath(workspaceRootPath)) {
    return;
  }
  Directory.current = workspaceRootPath;
}

Future<void> ensurePubGet() async {
  final packageConfig = File('.dart_tool/package_config.json');
  final stampFile = File(toolingStampPath);
  final currentStamp = _buildPubspecStamp();

  final needsPubGet =
      !packageConfig.existsSync() ||
      !stampFile.existsSync() ||
      stampFile.readAsStringSync() != currentStamp;

  if (!needsPubGet) {
    return;
  }

  await runFlutterOrExit(
    title: '依赖信息缺失或已过期，先执行 flutter pub get',
    arguments: const ['pub', 'get'],
  );

  stampFile.parent.createSync(recursive: true);
  stampFile.writeAsStringSync(_buildPubspecStamp());
}

void resetPubGetStamp() {
  final stampFile = File(toolingStampPath);
  if (stampFile.existsSync()) {
    stampFile.deleteSync();
  }
}

Future<void> runOrExit({
  required String title,
  required String executable,
  required List<String> arguments,
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  stdout.writeln('==> $title...');
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    exit(exitCode);
  }
}

Future<void> runFlutterOrExit({
  required String title,
  required List<String> arguments,
  String? workingDirectory,
}) async {
  await runOrExit(
    title: title,
    executable: flutterExecutable,
    arguments: arguments,
    workingDirectory: workingDirectory,
    environment: await androidBuildEnvironment(),
  );
}

Future<Map<String, String>> androidBuildEnvironment() async {
  final environment = Map<String, String>.from(Platform.environment);
  final runtime = await resolveAndroidJavaRuntime();
  if (runtime == null) {
    return environment;
  }

  environment['JAVA_HOME'] = runtime.home;
  environment['ORG_GRADLE_JAVA_HOME'] = runtime.home;

  final pathKey = _pathEnvironmentKey(environment);
  final pathListSeparator = Platform.isWindows ? ';' : ':';
  final javaBinPath = '${runtime.home}${Platform.pathSeparator}bin';
  final currentPath = environment[pathKey] ?? '';
  final pathEntries =
      currentPath
          .split(pathListSeparator)
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList();
  final containsJavaBin = pathEntries.any(
    (entry) => _normalizePath(entry) == _normalizePath(javaBinPath),
  );
  if (!containsJavaBin) {
    environment[pathKey] =
        currentPath.isEmpty
            ? javaBinPath
            : '$javaBinPath$pathListSeparator$currentPath';
  }

  return environment;
}

Future<AndroidJavaRuntime?> resolveAndroidJavaRuntime() async {
  final seenHomes = <String>{};
  for (final candidate in _androidJavaHomeCandidates()) {
    final normalized = _normalizePath(candidate.home);
    if (!seenHomes.add(normalized)) {
      continue;
    }

    final runtime = await _probeAndroidJavaRuntime(candidate);
    if (runtime != null) {
      return runtime;
    }
  }
  return null;
}

Iterable<_AndroidJavaCandidate> _androidJavaHomeCandidates() sync* {
  for (final environmentKey in const [
    'FLUXDO_ANDROID_JAVA_HOME',
    'ANDROID_STUDIO_JDK',
    'STUDIO_JDK',
    'JAVA21_HOME',
    'JAVA17_HOME',
  ]) {
    final value = Platform.environment[environmentKey];
    if (value != null && value.trim().isNotEmpty) {
      yield _AndroidJavaCandidate(value.trim(), environmentKey);
    }
  }

  yield* _androidStudioJavaCandidates();
  yield* _commonJavaHomeCandidates();

  final javaHome = Platform.environment['JAVA_HOME'];
  if (javaHome != null && javaHome.trim().isNotEmpty) {
    yield _AndroidJavaCandidate(javaHome.trim(), 'JAVA_HOME');
  }
}

Iterable<_AndroidJavaCandidate> _androidStudioJavaCandidates() sync* {
  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      final googleDir = Directory('$localAppData\\Google');
      if (googleDir.existsSync()) {
        final studioHomes =
            googleDir
                .listSync(followLinks: false)
                .whereType<Directory>()
                .where((directory) => directory.path.contains('AndroidStudio'))
                .map((directory) => File('${directory.path}\\.home'))
                .where((file) => file.existsSync());
        for (final homeFile in studioHomes) {
          final studioHome =
              homeFile.readAsLinesSync().firstWhere(
                (line) => line.trim().isNotEmpty,
                orElse: () => '',
              ).trim();
          if (studioHome.isEmpty) {
            continue;
          }
          yield _AndroidJavaCandidate(
            '$studioHome\\jbr',
            '${homeFile.path} -> jbr',
          );
          yield _AndroidJavaCandidate(
            '$studioHome\\jre',
            '${homeFile.path} -> jre',
          );
        }
      }
    }

    for (final root in const [
      r'C:\Program Files\Android\Android Studio',
      r'D:\Program Files\Android\Android Studio',
    ]) {
      yield _AndroidJavaCandidate('$root\\jbr', '$root\\jbr');
      yield _AndroidJavaCandidate('$root\\jre', '$root\\jre');
    }
    return;
  }

  if (Platform.isMacOS) {
    for (final root in const [
      '/Applications/Android Studio.app/Contents',
      '/Applications/Android Studio Preview.app/Contents',
    ]) {
      yield _AndroidJavaCandidate('$root/jbr/Contents/Home', '$root/jbr');
      yield _AndroidJavaCandidate('$root/jre/Contents/Home', '$root/jre');
    }
    return;
  }

  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    for (final root in [
      '$home/android-studio',
      '$home/android-studio-preview',
      '/opt/android-studio',
      '/snap/android-studio/current/android-studio',
    ]) {
      yield _AndroidJavaCandidate('$root/jbr', '$root/jbr');
      yield _AndroidJavaCandidate('$root/jre', '$root/jre');
    }
  }
}

Iterable<_AndroidJavaCandidate> _commonJavaHomeCandidates() sync* {
  if (!Platform.isWindows) {
    return;
  }

  for (final basePath in const [r'C:\Program Files\Java', r'D:\Program Files\Java']) {
    final baseDirectory = Directory(basePath);
    if (!baseDirectory.existsSync()) {
      continue;
    }

    for (final entity in baseDirectory.listSync(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      yield _AndroidJavaCandidate(entity.path, entity.path);
    }
  }
}

Future<AndroidJavaRuntime?> _probeAndroidJavaRuntime(
  _AndroidJavaCandidate candidate,
) async {
  final normalizedHome = _normalizePath(candidate.home);
  final javaExecutable =
      '$normalizedHome${Platform.pathSeparator}bin${Platform.pathSeparator}'
      '${Platform.isWindows ? 'java.exe' : 'java'}';
  final javaFile = File(javaExecutable);
  if (!javaFile.existsSync()) {
    return null;
  }

  try {
    final result = await Process.run(
      javaExecutable,
      const ['-version'],
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      return null;
    }

    final output = '${result.stdout}${result.stderr}';
    final match = RegExp(r'version "(\d+)').firstMatch(output);
    if (match == null) {
      return null;
    }

    final majorVersion = int.tryParse(match.group(1)!);
    if (majorVersion == null || majorVersion < 17 || majorVersion >= 26) {
      return null;
    }

    return AndroidJavaRuntime(
      home: normalizedHome,
      majorVersion: majorVersion,
      source: candidate.source,
    );
  } on ProcessException {
    return null;
  }
}

String _pathEnvironmentKey(Map<String, String> environment) {
  for (final key in environment.keys) {
    if (key.toLowerCase() == 'path') {
      return key;
    }
  }
  return Platform.isWindows ? 'Path' : 'PATH';
}

String _normalizePath(String path) {
  final normalized =
      path
          .replaceAll('/', Platform.pathSeparator)
          .replaceAll('\\', Platform.pathSeparator);
  if (Platform.isWindows) {
    return normalized.replaceAll(RegExp(r'[\\\/]+$'), '').toLowerCase();
  }
  return normalized.replaceAll(RegExp(r'[\\\/]+$'), '');
}

String _buildPubspecStamp() {
  final trackedFiles = <File>[
    File('pubspec.yaml'),
    File('pubspec.lock'),
    ..._packagePubspecFiles(),
  ].where((file) => file.existsSync()).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  return trackedFiles.map((file) {
    final stat = file.statSync();
    return '${file.path}|${stat.modified.millisecondsSinceEpoch}|${stat.size}';
  }).join('\n');
}

Iterable<File> _packagePubspecFiles() sync* {
  final packagesDir = Directory('packages');
  if (!packagesDir.existsSync()) {
    return;
  }

  for (final entity in packagesDir.listSync(followLinks: false)) {
    if (entity is! Directory) {
      continue;
    }
    yield File('${entity.path}${Platform.pathSeparator}pubspec.yaml');
  }
}

class AndroidJavaRuntime {
  const AndroidJavaRuntime({
    required this.home,
    required this.majorVersion,
    required this.source,
  });

  final String home;
  final int majorVersion;
  final String source;
}

class _AndroidJavaCandidate {
  const _AndroidJavaCandidate(this.home, this.source);

  final String home;
  final String source;
}

String _resolveWorkspaceRootPath() {
  final scriptDirectory = Directory.fromUri(Platform.script.resolve('.'));
  return scriptDirectory.parent.path;
}

String? _readNonBlankEnv(String key) {
  final value = Platform.environment[key]?.trim();
  return value == null || value.isEmpty ? null : value;
}

String? _resolveFlutterExecutableFromHome(String? flutterHome) {
  final normalizedHome = flutterHome?.trim();
  if (normalizedHome == null || normalizedHome.isEmpty) {
    return null;
  }

  final executable =
      '$normalizedHome${Platform.pathSeparator}bin${Platform.pathSeparator}'
      '${Platform.isWindows ? 'flutter.bat' : 'flutter'}';
  return File(executable).existsSync() ? executable : null;
}

String? _flutterHomeFromDartExecutable() {
  final normalized = Platform.resolvedExecutable.replaceAll('\\', '/');
  const marker = '/bin/cache/dart-sdk/bin/';
  final markerIndex = normalized.lastIndexOf(marker);
  if (markerIndex <= 0) {
    return null;
  }
  return normalized.substring(0, markerIndex).replaceAll('/', Platform.pathSeparator);
}

String? _flutterHomeFromIdeaDartSdk() {
  final ideaDartSdkFile = File('.idea/libraries/Dart_SDK.xml');
  if (!ideaDartSdkFile.existsSync()) {
    return null;
  }

  final match = RegExp(r'file://([^"]+?)[/\\]bin[/\\]cache[/\\]dart-sdk[/\\]lib[/\\]').firstMatch(
    ideaDartSdkFile.readAsStringSync(),
  );
  if (match == null) {
    return null;
  }

  return match.group(1)?.replaceAll('/', Platform.pathSeparator);
}
