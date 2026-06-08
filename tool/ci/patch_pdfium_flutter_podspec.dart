import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const _packageName = 'pdfium_flutter';
const _podspecRelativePath = 'darwin/pdfium_flutter.podspec';
const _upstreamHash =
    '948d9257f53f01cbed74b81bb8adc8758e52ac9390751772de7889026d32d5a1';
const _observedHash =
    'bef140a1a96994029153dca8c00b1750b9a5a764fb9db2dc68d7bb40e8a29e8a';

void main() {
  final packageConfigFile = File('.dart_tool/package_config.json');
  if (!packageConfigFile.existsSync()) {
    stderr.writeln(
      'Missing .dart_tool/package_config.json. Run flutter pub get first.',
    );
    exitCode = 64;
    return;
  }

  final packageConfig =
      jsonDecode(packageConfigFile.readAsStringSync()) as Map<String, Object?>;
  final packages = packageConfig['packages'] as List<Object?>;
  final pdfiumPackage = packages.cast<Map<String, Object?>>().firstWhere(
    (package) => package['name'] == _packageName,
    orElse: () => <String, Object?>{},
  );
  final rootUriValue = pdfiumPackage['rootUri'] as String?;
  if (rootUriValue == null) {
    stderr.writeln(
      'Package $_packageName was not found in package_config.json.',
    );
    exitCode = 65;
    return;
  }

  final packageConfigUri = packageConfigFile.absolute.parent.uri;
  final rootUri = _asDirectoryUri(packageConfigUri.resolve(rootUriValue));
  final podspec = File(p.fromUri(rootUri.resolve(_podspecRelativePath)));
  if (!podspec.existsSync()) {
    stderr.writeln('Missing $_packageName podspec at ${podspec.path}.');
    exitCode = 66;
    return;
  }

  final current = podspec.readAsStringSync();
  if (current.contains(_observedHash)) {
    stdout.writeln(
      '$_packageName podspec already uses the observed PDFium hash.',
    );
    return;
  }
  if (!current.contains(_upstreamHash)) {
    stderr.writeln(
      '$_packageName podspec does not contain the expected upstream hash. '
      'Revisit the temporary PDFium hash patch.',
    );
    exitCode = 67;
    return;
  }

  podspec.writeAsStringSync(current.replaceAll(_upstreamHash, _observedHash));
  stdout.writeln(
    'Patched $_packageName podspec PDFium hash for clean CI builds.',
  );
}

Uri _asDirectoryUri(Uri uri) {
  if (uri.path.endsWith('/')) {
    return uri;
  }
  return uri.replace(path: '${uri.path}/');
}
