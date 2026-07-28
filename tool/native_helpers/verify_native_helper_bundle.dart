import 'dart:io';

import 'package:path/path.dart' as p;

import 'native_helper_manifest.dart';
import 'native_helper_materializer.dart';

Future<void> main(List<String> args) async {
  try {
    final options = _Options.parse(args);
    final manifest = NativeHelperManifest.read(File(options.manifestPath));
    final emulatorRoot = options.emulatorRootPath == null
        ? nativeHelperRootForBundle(
            platform: options.platform,
            bundle: Directory(options.bundlePath!),
          )
        : Directory(options.emulatorRootPath!);
    await verifyNativeHelperBundle(
      platform: options.platform,
      emulatorRoot: emulatorRoot,
      expected: manifest,
    );
    stdout.writeln(
      'Verified ${options.platform} emulator helper bundle at '
      '${emulatorRoot.path}.',
    );
  } catch (error) {
    stderr.writeln('Failed to verify emulator helper bundle: $error');
    exitCode = 1;
  }
}

final class _Options {
  _Options({
    required this.platform,
    required this.bundlePath,
    required this.emulatorRootPath,
    required this.manifestPath,
  });

  factory _Options.parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (index + 1 >= args.length || !args[index].startsWith('--')) {
        throw const FormatException(
          'Verifier arguments must be --name value pairs.',
        );
      }
      values[args[index]] = args[index + 1];
    }
    final bundlePath = values['--bundle'];
    final emulatorRootPath = values['--emulator-root'];
    if ((bundlePath == null) == (emulatorRootPath == null)) {
      throw const FormatException(
        'Pass exactly one of --bundle or --emulator-root.',
      );
    }
    return _Options(
      platform: normalizeNativeHelperPlatform(
        values['--platform'] ?? Platform.operatingSystem,
      ),
      bundlePath: bundlePath,
      emulatorRootPath: emulatorRootPath,
      manifestPath:
          values['--manifest'] ??
          p.join('tool', 'native_helpers', 'native_helper_assets.json'),
    );
  }

  final String platform;
  final String? bundlePath;
  final String? emulatorRootPath;
  final String manifestPath;
}
