import 'dart:io';

import 'package:path/path.dart' as p;

import 'native_helper_manifest.dart';
import 'native_helper_materializer.dart';

Future<void> main(List<String> args) async {
  try {
    final options = _Options.parse(args);
    final manifest = NativeHelperManifest.read(File(options.manifestPath));
    await NativeHelperMaterializer(
      repositoryRoot: Directory.current,
      manifest: manifest,
    ).prepare(
      platform: options.platform,
      output: Directory(options.outputPath),
      cache: Directory(options.cachePath),
      offline: options.offline,
    );
    stdout.writeln(
      'Prepared verified ${options.platform} emulator helpers at '
      '${options.outputPath}.',
    );
  } catch (error) {
    stderr.writeln('Failed to prepare emulator helpers: $error');
    exitCode = 1;
  }
}

final class _Options {
  _Options({
    required this.platform,
    required this.outputPath,
    required this.cachePath,
    required this.manifestPath,
    required this.offline,
  });

  factory _Options.parse(List<String> args) {
    final values = <String, String>{};
    var offline = false;
    for (var index = 0; index < args.length; index += 1) {
      final argument = args[index];
      if (argument == '--offline') {
        offline = true;
        continue;
      }
      if (!argument.startsWith('--') || index + 1 >= args.length) {
        throw FormatException('Invalid native helper argument: $argument');
      }
      values[argument] = args[index + 1];
      index += 1;
    }
    final platform = normalizeNativeHelperPlatform(
      values['--platform'] ?? Platform.operatingSystem,
    );
    return _Options(
      platform: platform,
      outputPath:
          values['--output'] ??
          p.join('.dart_tool', 'alera_native_helpers', 'prepared', platform),
      cachePath:
          values['--cache'] ??
          p.join('.dart_tool', 'alera_native_helpers', 'cache'),
      manifestPath:
          values['--manifest'] ??
          p.join('tool', 'native_helpers', 'native_helper_assets.json'),
      offline: offline,
    );
  }

  final String platform;
  final String outputPath;
  final String cachePath;
  final String manifestPath;
  final bool offline;
}
