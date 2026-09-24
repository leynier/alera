import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final repository = Directory.current.absolute;
  final packageConfig = File.fromUri(
    repository.uri.resolve(
      'tool/release/runtime_packager/.dart_tool/package_config.json',
    ),
  );
  if (!packageConfig.existsSync()) {
    throw StateError('Resolve the standalone runtime packager first.');
  }
  final config = jsonDecode(packageConfig.readAsStringSync()) as Map;
  final packages = (config['packages'] as List).cast<Map>();
  if (packages.any((package) => package['name'] == 'flutter')) {
    throw StateError('The standalone packager must not depend on Flutter.');
  }
  final temporary = Directory.systemTemp.createTempSync(
    'alera_packager_check_',
  );
  try {
    final input = Directory.fromUri(temporary.uri.resolve('input/'));
    final output = Directory.fromUri(temporary.uri.resolve('output/'));
    for (final platform in ['linux', 'macos', 'windows']) {
      for (final architecture in ['x64', 'arm64']) {
        final directory = Directory.fromUri(
          input.uri.resolve('$platform/$architecture/'),
        )..createSync(recursive: true);
        final name = platform == 'windows' ? 'alera.exe' : 'alera';
        File.fromUri(directory.uri.resolve(name))
            .writeAsStringSync('$platform-$architecture');
      }
    }
    final script = File.fromUri(
      repository.uri.resolve('tool/release/package_runtime_sidecars.dart'),
    );
    final result = await Process.run(Platform.resolvedExecutable, [
      '--packages=${packageConfig.path}',
      script.path,
      '--version',
      '0.0.0',
      '--input',
      input.path,
      '--output',
      output.path,
    ]);
    if (result.exitCode != 0) {
      throw StateError('Standalone packaging failed: ${result.stderr}');
    }
    final files = output.listSync().whereType<File>().toList();
    if (files.length != 12 ||
        files.where((file) => file.path.endsWith('.tar.gz')).length != 6) {
      throw StateError('Expected six archives and six checksums.');
    }
    stdout.writeln(
      'Standalone Dart packager produced all six runtime archives.',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}
