import 'dart:io';

import 'package:path/path.dart' as p;

import 'native_helper_manifest.dart';
import 'native_helper_materializer.dart';
import 'video_runtime_verifier.dart';

Future<void> main(List<String> args) async {
  try {
    final options = _Options.parse(args);
    final bundle = Directory(options.bundlePath);
    final helperManifest = NativeHelperManifest.read(
      File(options.helperManifestPath),
    );
    await verifyNativeHelperBundle(
      platform: options.platform,
      emulatorRoot: nativeHelperRootForBundle(
        platform: options.platform,
        bundle: bundle,
      ),
      expected: helperManifest,
    );
    await verifyVideoRuntimeBundle(
      platform: options.platform,
      bundle: bundle,
      manifestFile: File(options.videoManifestPath),
    );
    stdout.writeln(
      'Verified ${options.platform} helper and video runtimes in '
      '${bundle.path}.',
    );
  } catch (error) {
    stderr.writeln('Failed to verify desktop runtime bundle: $error');
    exitCode = 1;
  }
}

final class _Options({
  required final String platform,
  required final String bundlePath,
  required final String helperManifestPath,
  required final String videoManifestPath,
}) {
  factory parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (index + 1 >= args.length || !args[index].startsWith('--')) {
        throw const FormatException(
          'Verifier arguments must be --name value pairs.',
        );
      }
      values[args[index]] = args[index + 1];
    }
    final bundle = values['--bundle'];
    if (bundle == null || bundle.isEmpty) {
      throw const FormatException('--bundle is required.');
    }
    return _Options(
      platform: normalizeNativeHelperPlatform(
        values['--platform'] ?? Platform.operatingSystem,
      ),
      bundlePath: bundle,
      helperManifestPath:
          values['--helper-manifest'] ??
          p.join('tool', 'native_helpers', 'native_helper_assets.json'),
      videoManifestPath:
          values['--video-manifest'] ??
          p.join('tool', 'native_helpers', 'video_runtime_assets.json'),
    );
  }
}
