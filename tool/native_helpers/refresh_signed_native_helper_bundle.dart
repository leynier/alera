import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'native_helper_manifest.dart';
import 'native_helper_materializer.dart';

Future<void> main(List<String> arguments) async {
  try {
    final options = _RefreshOptions.parse(arguments);
    final expected = NativeHelperManifest.read(File(options.manifestPath));
    await refreshSignedMacosNativeHelperBundle(
      emulatorRoot: Directory(options.emulatorRoot),
      expected: expected,
    );
    stdout.writeln(
      'Refreshed signed macOS native helper bundle at '
      '${options.emulatorRoot}.',
    );
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

Future<void> refreshSignedMacosNativeHelperBundle({
  required Directory emulatorRoot,
  required NativeHelperManifest expected,
}) async {
  final generatedFile = File(p.join(emulatorRoot.path, 'manifest.json'));
  if (!generatedFile.existsSync()) {
    throw StateError(
      'Missing generated native helper manifest: ${generatedFile.path}',
    );
  }
  final decoded = jsonDecode(generatedFile.readAsStringSync());
  if (decoded is! Map<String, Object?> ||
      decoded['schemaVersion'] != expected.schemaVersion ||
      decoded['generatedBy'] != nativeHelperBundleGenerator ||
      decoded['platform'] != 'macos') {
    throw const FormatException(
      'Only a generated macOS native helper bundle can be refreshed.',
    );
  }

  final rawAssets = decoded['assets'];
  if (rawAssets is! List<Object?>) {
    throw const FormatException(
      'Generated native helper assets must be an array.',
    );
  }
  final generatedIds = <String>{};
  for (final value in rawAssets) {
    if (value is! Map<String, Object?> ||
        value['id'] is! String ||
        !generatedIds.add(value['id']! as String)) {
      throw const FormatException('Generated native helper asset is invalid.');
    }
  }
  final expectedAssets = expected.assetsFor('macos');
  final expectedIds = expectedAssets.map((asset) => asset.id).toSet();
  if (generatedIds.difference(expectedIds).isNotEmpty ||
      expectedIds.difference(generatedIds).isNotEmpty) {
    throw StateError(
      'Native helper bundle asset set does not match the source manifest.',
    );
  }

  final payloadSha256ById = <String, String>{};
  for (final asset in expectedAssets) {
    final payload = File(
      p.join(emulatorRoot.path, p.fromUri(asset.relativePath)),
    );
    if (!payload.existsSync()) {
      throw StateError('${asset.id} payload is missing: ${payload.path}');
    }
    final digest = await fileSha256(payload);
    final pinnedDigest = asset.payloadSha256;
    if (pinnedDigest != null && digest != pinnedDigest) {
      throw StateError(
        '${asset.id} is pinned and cannot change during macOS signing.',
      );
    }
    payloadSha256ById[asset.id] = digest;
  }

  await generatedFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(expected.bundleJson('macos', payloadSha256ById: payloadSha256ById))}\n',
    flush: true,
  );
  await verifyNativeHelperBundle(
    platform: 'macos',
    emulatorRoot: emulatorRoot,
    expected: expected,
  );
}

final class const _RefreshOptions({
  required final String emulatorRoot,
  required final String manifestPath,
}) {
  factory parse(List<String> arguments) {
    final values = <String, String>{};
    for (var index = 0; index < arguments.length; index += 2) {
      if (index + 1 >= arguments.length || !arguments[index].startsWith('--')) {
        throw const FormatException(
          'Expected --emulator-root PATH and optional --manifest PATH.',
        );
      }
      values[arguments[index]] = arguments[index + 1];
    }
    final emulatorRoot = values['--emulator-root'];
    if (emulatorRoot == null ||
        values.keys.any(
          (key) => key != '--emulator-root' && key != '--manifest',
        )) {
      throw const FormatException(
        'Expected --emulator-root PATH and optional --manifest PATH.',
      );
    }
    return _RefreshOptions(
      emulatorRoot: emulatorRoot,
      manifestPath:
          values['--manifest'] ??
          'tool/native_helpers/native_helper_assets.json',
    );
  }
}
