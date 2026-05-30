part of 'alera_debug.dart';

Future<int> _run(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  bool forwardStdin = false,
  bool normalizeDartBuildOutput = false,
  String? workingDirectory,
}) async {
  stdout.writeln([executable, ...arguments].map(_quoteForLog).join(' '));
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory ?? _repoRoot,
    environment: environment,
    includeParentEnvironment: true,
    runInShell: Platform.isWindows,
  );
  StreamSubscription<List<int>>? stdinSub;
  if (forwardStdin && stdin.hasTerminal) {
    stdinSub = stdin.listen(
      process.stdin.add,
      onError: process.stdin.addError,
      onDone: process.stdin.close,
    );
  }
  final stdoutDone = normalizeDartBuildOutput
      ? _writeNormalizedDartBuildOutput(process.stdout, stdout)
      : stdout.addStream(process.stdout);
  final stderrDone = normalizeDartBuildOutput
      ? _writeNormalizedDartBuildOutput(process.stderr, stderr)
      : stderr.addStream(process.stderr);
  final processExit = await process.exitCode;
  await stdinSub?.cancel();
  await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
  return processExit;
}

Future<void> _writeNormalizedDartBuildOutput(
  Stream<List<int>> stream,
  IOSink sink,
) async {
  final output = StringBuffer();
  await for (final chunk in utf8.decoder.bind(stream)) {
    output.write(chunk);
  }
  sink.write(_DartBuildOutputNormalizer().convert(output.toString()));
}

final class _DartBuildOutputNormalizer {
  static const _markers = <String>[
    'Running build hooks...',
    'Running link hooks...',
    'Copying ',
  ];

  int? _lastCodeUnit;

  String convert(String value) {
    final output = StringBuffer();
    for (var index = 0; index < value.length;) {
      final marker = _markers.where(
        (marker) => value.startsWith(marker, index),
      );
      if (marker.isNotEmpty && _needsLineBreakBeforeMarker) {
        output.writeln();
        _lastCodeUnit = 10;
      }
      final codeUnit = value.codeUnitAt(index);
      output.writeCharCode(codeUnit);
      _lastCodeUnit = codeUnit;
      index += 1;
    }
    return output.toString();
  }

  bool get _needsLineBreakBeforeMarker {
    final lastCodeUnit = _lastCodeUnit;
    return lastCodeUnit != null && lastCodeUnit != 10 && lastCodeUnit != 13;
  }
}

Future<List<_ProcessInfo>> _listProcesses() async {
  if (Platform.isWindows) {
    final executable = await _firstAvailableExecutable(<String>[
      'pwsh',
      'powershell',
    ]);
    if (executable == null) {
      stderr.writeln(
        'PowerShell 7 is required on Windows for debug-processes.',
      );
      return const <_ProcessInfo>[];
    }
    final result = await Process.run(executable, <String>[
      '-NoLogo',
      '-NoProfile',
      '-Command',
      r'Get-CimInstance Win32_Process | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress',
    ]);
    if (result.exitCode != 0) {
      stderr.writeln(result.stderr);
      return const <_ProcessInfo>[];
    }
    final raw = (result.stdout as String).trim();
    if (raw.isEmpty) {
      return const <_ProcessInfo>[];
    }
    final decoded = jsonDecode(raw);
    final entries = decoded is List ? decoded : <Object?>[decoded];
    return entries.whereType<Map<Object?, Object?>>().map((entry) {
      return _ProcessInfo(
        pid: (entry['ProcessId'] as num).toInt(),
        commandLine: (entry['CommandLine'] as String?) ?? '',
      );
    }).toList();
  }

  final result = await Process.run('ps', const <String>[
    '-ax',
    '-o',
    'pid=,command=',
  ]);
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    return const <_ProcessInfo>[];
  }
  return LineSplitter.split(result.stdout as String)
      .map((line) {
        final trimmed = line.trimLeft();
        final firstSpace = trimmed.indexOf(' ');
        if (firstSpace < 0) {
          return _ProcessInfo(pid: -1, commandLine: trimmed);
        }
        return _ProcessInfo(
          pid: int.tryParse(trimmed.substring(0, firstSpace)) ?? -1,
          commandLine: trimmed.substring(firstSpace + 1).trimLeft(),
        );
      })
      .where((process) => process.pid >= 0)
      .toList();
}

Future<String?> _firstAvailableExecutable(List<String> executables) async {
  for (final executable in executables) {
    final result = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      <String>[executable],
    );
    if (result.exitCode == 0) {
      return executable;
    }
  }
  return null;
}

String _defaultAppSupportDir(String appId) {
  final environment = Platform.environment;
  if (Platform.isMacOS) {
    return _join(_homeDirectory, 'Library', 'Application Support', appId);
  }
  if (Platform.isWindows) {
    final appData = environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return _join(appData, appId);
    }
  }
  final xdgDataHome = environment['XDG_DATA_HOME'];
  if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
    return _join(xdgDataHome, appId);
  }
  return _join(_homeDirectory, '.local', 'share', appId);
}

String get _homeDirectory {
  final environment = Platform.environment;
  return environment['HOME'] ??
      environment['USERPROFILE'] ??
      Directory.current.path;
}

String get _repoRoot => Directory.current.absolute.path;

String _join(
  String first,
  String second, [
  String? third,
  String? fourth,
  String? fifth,
]) {
  final parts = <String>[first, second, ?third, ?fourth, ?fifth];
  final buffer = StringBuffer(parts.first.replaceAll(RegExp(r'[/\\]+$'), ''));
  for (final part in parts.skip(1)) {
    final normalized = part
        .replaceAll(RegExp(r'^[/\\]+'), '')
        .replaceAll(RegExp(r'[/\\]+$'), '');
    if (normalized.isEmpty) {
      continue;
    }
    buffer
      ..write(Platform.pathSeparator)
      ..write(normalized);
  }
  return buffer.toString();
}

String _normalizeSeparators(String value) {
  return value.replaceAll(r'\', '/');
}

String _normalizeProcessText(String value) {
  return _normalizeSeparators(value).toLowerCase();
}

bool _containsNormalizedPathRoot(String value, String pathRoot) {
  return value.contains('$pathRoot/') ||
      value.contains('$pathRoot ') ||
      value.contains('$pathRoot"') ||
      value.contains("$pathRoot'") ||
      value.endsWith(pathRoot);
}

String _quoteForLog(String value) {
  if (value.contains(' ') || value.contains('\t')) {
    return '"$value"';
  }
  return value;
}
