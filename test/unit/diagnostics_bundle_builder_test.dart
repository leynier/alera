import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/diagnostics/domain/diagnostics_bundle_metadata.dart';
import 'package:alera/src/features/diagnostics/infra/diagnostics_bundle_builder.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory appLogs;
  late Directory runtimeLogs;

  setUp(() {
    root = Directory.systemTemp.createTempSync('alera-bundle');
    appLogs = Directory('${root.path}/app-logs')..createSync();
    runtimeLogs = Directory('${root.path}/runtime-logs')..createSync();
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  DiagnosticsBundleMetadata metadata({
    String? runtimeVersion,
    List<String> capabilities = const <String>[],
  }) {
    return DiagnosticsBundleMetadata(
      appVersion: '0.34.0+63',
      flavor: 'dev',
      operatingSystem: 'linux',
      operatingSystemVersion: 'test-kernel',
      collectedAt: .utc(2026, 7, 28, 12),
      runtimeHostVersion: runtimeVersion,
      runtimeHostCommit: runtimeVersion == null ? null : 'abc1234',
      protocolVersion: runtimeVersion == null ? null : 4,
      runtimeCapabilities: capabilities,
    );
  }

  Archive decode(List<int> bytes) => ZipDecoder().decodeBytes(bytes);

  String readEntry(Archive archive, String name) {
    final file = archive.files.firstWhere((entry) => entry.name == name);
    return utf8.decode(file.content as List<int>);
  }

  test('packs app and runtime logs under separate prefixes', () {
    File('${appLogs.path}/alera.log').writeAsStringSync('{"msg":"app line"}');
    File('${runtimeLogs.path}/runtime.log')
        .writeAsStringSync('{"msg":"runtime line"}');

    final archive = decode(
      const DiagnosticsBundleBuilder().build(
        metadata: metadata(runtimeVersion: '0.1.0'),
        appLogDirectory: appLogs,
        runtimeLogDirectory: runtimeLogs,
      ),
    );

    expect(readEntry(archive, 'app/alera.log'), contains('app line'));
    expect(readEntry(archive, 'runtime/runtime.log'), contains('runtime line'));
  });

  test('records versions and capabilities in the metadata entry', () {
    final archive = decode(
      const DiagnosticsBundleBuilder().build(
        metadata: metadata(
          runtimeVersion: '0.1.0',
          capabilities: <String>['hostDiagnosticsLogsV1'],
        ),
        appLogDirectory: appLogs,
        runtimeLogDirectory: runtimeLogs,
      ),
    );

    final meta =
        jsonDecode(readEntry(archive, 'meta.json')) as Map<String, Object?>;
    expect((meta['app']! as Map<String, Object?>)['version'], '0.34.0+63');
    expect((meta['app']! as Map<String, Object?>)['flavor'], 'dev');
    final runtime = meta['runtime']! as Map<String, Object?>;
    expect(runtime['reachable'], isTrue);
    expect(runtime['version'], '0.1.0');
    expect(runtime['protocolVersion'], 4);
    expect(runtime['capabilities'], contains('hostDiagnosticsLogsV1'));
  });

  test('marks the runtime unreachable when it could not be probed', () {
    final archive = decode(
      const DiagnosticsBundleBuilder().build(
        metadata: metadata(),
        appLogDirectory: appLogs,
      ),
    );

    final meta =
        jsonDecode(readEntry(archive, 'meta.json')) as Map<String, Object?>;
    expect((meta['runtime']! as Map<String, Object?>)['reachable'], isFalse);
  });

  test('skips a missing log directory rather than failing', () {
    final archive = decode(
      const DiagnosticsBundleBuilder().build(
        metadata: metadata(),
        appLogDirectory: Directory('${root.path}/does-not-exist'),
        runtimeLogDirectory: Directory('${root.path}/also-missing'),
      ),
    );

    expect(archive.files.map((file) => file.name), <String>['meta.json']);
  });

  test('ignores files that are not logs', () {
    File('${appLogs.path}/alera.log').writeAsStringSync('kept');
    File('${appLogs.path}/notes.txt').writeAsStringSync('dropped');

    final archive = decode(
      const DiagnosticsBundleBuilder().build(
        metadata: metadata(),
        appLogDirectory: appLogs,
      ),
    );

    expect(
      archive.files.map((file) => file.name),
      containsAll(<String>['app/alera.log', 'meta.json']),
    );
    expect(
      archive.files.map((file) => file.name),
      isNot(contains('notes.txt')),
    );
  });

  test('suggested file name is filesystem safe', () {
    final name = DiagnosticsBundleBuilder.suggestedFileName(
      .utc(2026, 7, 28, 12, 30, 15),
    );

    expect(name, 'alera-diagnostics-20260728T123015.zip');
    expect(name, isNot(contains(':')));
  });
}
