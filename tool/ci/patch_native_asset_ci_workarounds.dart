import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const _packageName = 'pdfium_flutter';
const _pdfiumDartPackageName = 'pdfium_dart';
const _sqlitePackageName = 'sqlite3';
const _podspecRelativePath = 'darwin/pdfium_flutter.podspec';
const _pdfiumDartBuildHookRelativePath = 'hook/build.dart';
const _sqliteDescriptionRelativePath = 'lib/src/hook/description.dart';
const _upstreamHash =
    '948d9257f53f01cbed74b81bb8adc8758e52ac9390751772de7889026d32d5a1';
const _observedHash =
    'bef140a1a96994029153dca8c00b1750b9a5a764fb9db2dc68d7bb40e8a29e8a';
const _pdfiumDartDownloadSnippet = '''
  final response = await http.Client().get(archiveUri);
  if (response.statusCode != 200) {
    throw Exception('Failed to download PDFium: \$archiveUri');
  }
''';
const _pdfiumDartRetriedDownloadSnippet = '''
  final client = http.Client();
  http.Response? response;
  try {
    for (var attempt = 1; attempt <= 6; attempt++) {
      try {
        response = await client.get(archiveUri);
        if (response.statusCode == 200) break;

        stderr.writeln(
          'PDFium download attempt \$attempt failed with status '
          '\${response.statusCode}: \$archiveUri',
        );
      } catch (error) {
        if (attempt == 6) rethrow;
        stderr.writeln(
          'PDFium download attempt \$attempt failed: \$error',
        );
      }

      await Future<void>.delayed(Duration(seconds: attempt * 10));
    }
  } finally {
    client.close();
  }

  if (response == null || response.statusCode != 200) {
    throw Exception('Failed to download PDFium: \$archiveUri');
  }
''';
const _sqliteDownloadSnippet = '''
    final tmp = File('\${downloadedFile.path}.tmp');
    await fetch(input, output, library).cast<List<int>>().pipe(tmp.openWrite());
    tmp.renameSync(downloadedFile.path);
    return downloadedFile;
''';
const _sqliteRetriedDownloadSnippet = '''
    final tmp = File('\${downloadedFile.path}.tmp');
    for (var attempt = 1; attempt <= 6; attempt++) {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
        await fetch(input, output, library)
            .cast<List<int>>()
            .pipe(tmp.openWrite());
        tmp.renameSync(downloadedFile.path);
        return downloadedFile;
      } catch (error) {
        if (attempt == 6) rethrow;
        stderr.writeln(
          'SQLite download attempt \$attempt failed: \$error',
        );
        await Future<void>.delayed(Duration(seconds: attempt * 10));
      }
    }

    throw StateError('Failed to download SQLite: \${library.sourceFilename}');
''';
const _sqliteUriSnippet = '''
    final uri = Uri.https(
      'github.com',
      'simolus3/sqlite3.dart/releases/download/\${releaseTag!}/\$filename',
    );
''';
const _sqliteCacheBustedUriSnippet = '''
    final uri = Uri.https(
      'github.com',
      'simolus3/sqlite3.dart/releases/download/\${releaseTag!}/\$filename',
      {'ci_cache_bust': DateTime.now().microsecondsSinceEpoch.toString()},
    );
''';

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
  final typedPackages = packages.cast<Map<String, Object?>>();
  final pdfiumPackage = _findPackage(typedPackages, _packageName);
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
  } else if (!current.contains(_upstreamHash)) {
    stderr.writeln(
      '$_packageName podspec does not contain the expected upstream hash. '
      'Revisit the temporary PDFium hash patch.',
    );
    exitCode = 67;
    return;
  } else {
    podspec.writeAsStringSync(current.replaceAll(_upstreamHash, _observedHash));
    stdout.writeln(
      'Patched $_packageName podspec PDFium hash for clean CI builds.',
    );
  }

  final pdfiumDartPackage = _findPackage(typedPackages, _pdfiumDartPackageName);
  final pdfiumDartRootUriValue = pdfiumDartPackage['rootUri'] as String?;
  if (pdfiumDartRootUriValue == null) {
    stderr.writeln(
      'Package $_pdfiumDartPackageName was not found in package_config.json.',
    );
    exitCode = 68;
    return;
  }

  final pdfiumDartRootUri = _asDirectoryUri(
    packageConfigUri.resolve(pdfiumDartRootUriValue),
  );
  final pdfiumDartBuildHook = File(
    p.fromUri(pdfiumDartRootUri.resolve(_pdfiumDartBuildHookRelativePath)),
  );
  if (!pdfiumDartBuildHook.existsSync()) {
    stderr.writeln(
      'Missing $_pdfiumDartPackageName build hook at '
      '${pdfiumDartBuildHook.path}.',
    );
    exitCode = 69;
    return;
  }

  final currentBuildHook = pdfiumDartBuildHook.readAsStringSync();
  if (currentBuildHook.contains(_pdfiumDartRetriedDownloadSnippet)) {
    stdout.writeln(
      '$_pdfiumDartPackageName build hook already retries PDFium downloads.',
    );
  } else if (!currentBuildHook.contains(_pdfiumDartDownloadSnippet)) {
    stderr.writeln(
      '$_pdfiumDartPackageName build hook does not contain the expected '
      'download snippet. Revisit the temporary PDFium download retry patch.',
    );
    exitCode = 70;
    return;
  } else {
    pdfiumDartBuildHook.writeAsStringSync(
      currentBuildHook.replaceAll(
        _pdfiumDartDownloadSnippet,
        _pdfiumDartRetriedDownloadSnippet,
      ),
    );
    stdout.writeln(
      'Patched $_pdfiumDartPackageName build hook to retry PDFium downloads.',
    );
  }

  final pdfiumDartHookCache = Directory(
    p.join('.dart_tool', 'hooks_runner', _pdfiumDartPackageName),
  );
  if (pdfiumDartHookCache.existsSync()) {
    pdfiumDartHookCache.deleteSync(recursive: true);
    stdout.writeln(
      'Removed cached $_pdfiumDartPackageName hook output so CI recompiles it.',
    );
  }

  final sqlitePackage = _findPackage(typedPackages, _sqlitePackageName);
  final sqliteRootUriValue = sqlitePackage['rootUri'] as String?;
  if (sqliteRootUriValue == null) {
    stderr.writeln(
      'Package $_sqlitePackageName was not found in package_config.json.',
    );
    exitCode = 71;
    return;
  }

  final sqliteRootUri = _asDirectoryUri(
    packageConfigUri.resolve(sqliteRootUriValue),
  );
  final sqliteDescription = File(
    p.fromUri(sqliteRootUri.resolve(_sqliteDescriptionRelativePath)),
  );
  if (!sqliteDescription.existsSync()) {
    stderr.writeln(
      'Missing $_sqlitePackageName hook description at '
      '${sqliteDescription.path}.',
    );
    exitCode = 72;
    return;
  }

  var currentSqliteDescription = sqliteDescription.readAsStringSync();
  if (currentSqliteDescription.contains(_sqliteRetriedDownloadSnippet)) {
    stdout.writeln(
      '$_sqlitePackageName hook already retries SQLite downloads.',
    );
  } else if (!currentSqliteDescription.contains(_sqliteDownloadSnippet)) {
    stderr.writeln(
      '$_sqlitePackageName hook does not contain the expected download '
      'snippet. Revisit the temporary SQLite retry patch.',
    );
    exitCode = 73;
    return;
  } else {
    currentSqliteDescription = currentSqliteDescription.replaceAll(
      _sqliteDownloadSnippet,
      _sqliteRetriedDownloadSnippet,
    );
    sqliteDescription.writeAsStringSync(currentSqliteDescription);
    stdout.writeln(
      'Patched $_sqlitePackageName hook to retry SQLite downloads.',
    );
  }

  currentSqliteDescription = sqliteDescription.readAsStringSync();
  if (currentSqliteDescription.contains(_sqliteCacheBustedUriSnippet)) {
    stdout.writeln(
      '$_sqlitePackageName hook already cache-busts SQLite downloads.',
    );
  } else if (!currentSqliteDescription.contains(_sqliteUriSnippet)) {
    stderr.writeln(
      '$_sqlitePackageName hook does not contain the expected GitHub URI '
      'snippet. Revisit the temporary SQLite cache-busting patch.',
    );
    exitCode = 74;
    return;
  } else {
    sqliteDescription.writeAsStringSync(
      currentSqliteDescription.replaceAll(
        _sqliteUriSnippet,
        _sqliteCacheBustedUriSnippet,
      ),
    );
    stdout.writeln(
      'Patched $_sqlitePackageName hook to cache-bust SQLite downloads.',
    );
  }

  for (final path in [
    p.join('.dart_tool', 'hooks_runner', _sqlitePackageName),
    p.join('.dart_tool', 'hooks_runner', 'shared', _sqlitePackageName),
  ]) {
    final directory = Directory(path);
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
      stdout.writeln(
        'Removed cached $_sqlitePackageName hook output at $path.',
      );
    }
  }
}

Map<String, Object?> _findPackage(
  Iterable<Map<String, Object?>> packages,
  String name,
) {
  return packages.firstWhere(
    (package) => package['name'] == name,
    orElse: () => <String, Object?>{},
  );
}

Uri _asDirectoryUri(Uri uri) {
  if (uri.path.endsWith('/')) {
    return uri;
  }
  return uri.replace(path: '${uri.path}/');
}
