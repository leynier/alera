import 'dart:io';

Future<void> main(List<String> arguments) async {
  final environment = Platform.environment;
  final repoRoot =
      environment['ALERA_DEBUG_REPO_ROOT'] ?? Directory.current.path;
  final dartExecutable = environment['ALERA_DEBUG_DART'] ?? 'dart';
  final debugPort = environment['ALERA_CLI_DEBUG_PORT'] ?? '8181';
  final scriptPath = _join(repoRoot, 'bin', 'alera.dart');

  await Process.start(
    dartExecutable,
    <String>['--observe=$debugPort/127.0.0.1', scriptPath, ...arguments],
    workingDirectory: repoRoot,
    mode: ProcessStartMode.detached,
    includeParentEnvironment: true,
    runInShell: Platform.isWindows,
  );
}

String _join(String first, String second, [String? third]) {
  final parts = <String>[first, second, ?third];
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
