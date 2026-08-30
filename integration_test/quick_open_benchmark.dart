/// Measures Quick Open indexing and native query latency against 40,000 files.
///
/// This is a non-gating comparison benchmark rather than a CI test. It creates
/// a fresh temporary workspace, reports the scan duration and p50/p95 for 100
/// FRB queries, and cleans the workspace up afterward.
///
///     flutter test integration_test/quick_open_benchmark.dart -d linux
library;

import 'dart:io';

import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:alera/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

const _fileCount = 40_000;
const _queryCount = 100;
const _resultLimit = 50;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('quick open 40k path benchmark', (tester) async {
    await RustLib.init();
    final workspace = await _createWorkspace();
    addTearDown(() => workspace.delete(recursive: true));

    final scanTimer = Stopwatch()..start();
    final session = await native.startWorkspaceQuickOpenSession(
      workspacePath: workspace.path,
    );
    scanTimer.stop();
    expect(session.indexedFileCount, _fileCount);

    final queryDurations = <int>[];
    for (var index = 0; index < _queryCount; index++) {
      final query = switch (index % 4) {
        0 => 'file_${index.toString().padLeft(5, '0')}',
        1 => 'group_${(index % 200).toString().padLeft(3, '0')}',
        2 => 'file_${(index % 40).toString()}',
        _ => 'no-match-$index',
      };
      final timer = Stopwatch()..start();
      final matches = await native.searchWorkspaceQuickOpenSession(
        session: session,
        query: query,
        limit: _resultLimit,
      );
      timer.stop();
      expect(matches.length, lessThanOrEqualTo(_resultLimit));
      queryDurations.add(timer.elapsedMicroseconds);
    }
    await native.stopWorkspaceQuickOpenSession(session: session);

    queryDurations.sort();
    final p50 = queryDurations[queryDurations.length ~/ 2];
    final p95 = queryDurations[((queryDurations.length * 95) ~/ 100) - 1];
    // ignore: avoid_print
    print(
      'quick open benchmark: '
      'indexed=${session.indexedFileCount} '
      'scan=${scanTimer.elapsedMilliseconds} ms '
      'queries=$_queryCount '
      'p50=${(p50 / 1000).toStringAsFixed(2)} ms '
      'p95=${(p95 / 1000).toStringAsFixed(2)} ms',
    );
  });
}

Future<Directory> _createWorkspace() async {
  final workspace = await Directory.systemTemp.createTemp(
    'alera_quick_open_benchmark_',
  );
  final groups = <Directory>[];
  for (var index = 0; index < 200; index++) {
    final group = Directory(
      p.join(workspace.path, 'group_${index.toString().padLeft(3, '0')}'),
    );
    await group.create();
    groups.add(group);
  }
  for (var index = 0; index < _fileCount; index++) {
    final group = groups[index % groups.length];
    File(p.join(group.path, 'file_${index.toString().padLeft(5, '0')}.txt'))
        .writeAsStringSync('');
  }
  return workspace;
}
