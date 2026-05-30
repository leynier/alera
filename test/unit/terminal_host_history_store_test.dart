import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_history_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'dart:io';

void main() {
  test(
    'TerminalHostHistoryStore creates, reads, deletes, and closes checkpoints',
    () {
      final root = Directory.systemTemp.createTempSync('alera-history-store-');
      addTearDown(() {
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
      });
      final runtimeDir = Directory(p.join(root.path, 'runtime'));
      final store = TerminalHostHistoryStore.open(runtimeDir: runtimeDir);
      addTearDown(store.close);
      final now = DateTime.utc(2026, 5, 28, 12);
      final endedAt = DateTime.utc(2026, 5, 28, 12, 1);

      store.upsert(
        TerminalHostCheckpoint(
          sessionId: 'session-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
          workingDirectory: '/tmp/project',
          running: false,
          exitCode: 0,
          endedAt: endedAt,
          updatedAt: now,
          buffer: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      );

      final restored = store.read('session-1')!;
      expect(runtimeDir.existsSync(), isTrue);
      expect(restored.running, isFalse);
      expect(restored.exitCode, 0);
      expect(restored.endedAt, endedAt);
      expect(restored.updatedAt, now);
      expect(restored.buffer, <int>[1, 2, 3]);

      store.delete('session-1');
      expect(store.read('session-1'), isNull);
      store.close();
      store.close();
      expect(() => store.read('session-1'), throwsStateError);
    },
  );

  test('TerminalHostHistoryStore tolerates invalid raw row values', () {
    final root = Directory.systemTemp.createTempSync(
      'alera-history-store-raw-',
    );
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });
    final runtimeDir = Directory(p.join(root.path, 'runtime'));
    TerminalHostHistoryStore.open(runtimeDir: runtimeDir).close();
    final database = sqlite.sqlite3.open(
      p.join(runtimeDir.path, terminalHostHistoryDatabaseFileName),
    );
    database.execute(
      '''
      INSERT INTO checkpoints
        (sessionId, workspaceId, tabId, workingDirectory, running, exitCode,
         endedAt, updatedAt, buffer)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      <Object?>[
        'session-raw',
        'workspace-1',
        'tab-1',
        '/tmp/project',
        1,
        null,
        '',
        'not a date',
        'not bytes',
      ],
    );
    database.close();

    final store = TerminalHostHistoryStore.open(runtimeDir: runtimeDir);
    addTearDown(store.close);
    final restored = store.read('session-raw')!;

    expect(restored.running, isTrue);
    expect(restored.endedAt, isNull);
    expect(
      restored.updatedAt,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    expect(restored.buffer, isEmpty);
  });
}
