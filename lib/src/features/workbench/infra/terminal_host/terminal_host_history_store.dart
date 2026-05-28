import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

const String terminalHostHistoryDatabaseFileName = 'terminal_history.sqlite';

final class TerminalHostCheckpoint {
  const TerminalHostCheckpoint({
    required this.sessionId,
    required this.workspaceId,
    required this.tabId,
    required this.workingDirectory,
    required this.running,
    required this.exitCode,
    required this.endedAt,
    required this.updatedAt,
    required this.buffer,
  });

  factory TerminalHostCheckpoint.fromRow(sqlite.Row row) {
    return TerminalHostCheckpoint(
      sessionId: row['sessionId'] as String,
      workspaceId: row['workspaceId'] as String,
      tabId: row['tabId'] as String,
      workingDirectory: row['workingDirectory'] as String,
      running: row['running'] == 1,
      exitCode: row['exitCode'] as int?,
      endedAt: _dateTimeOrNull(row['endedAt']),
      updatedAt:
          DateTime.tryParse(row['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      buffer: _blob(row['buffer']),
    );
  }

  final String sessionId;
  final String workspaceId;
  final String tabId;
  final String workingDirectory;
  final bool running;
  final int? exitCode;
  final DateTime? endedAt;
  final DateTime updatedAt;
  final Uint8List buffer;
}

final class TerminalHostHistoryStore {
  TerminalHostHistoryStore._(this.file, this._database);

  factory TerminalHostHistoryStore.open({required Directory runtimeDir}) {
    if (!runtimeDir.existsSync()) {
      runtimeDir.createSync(recursive: true);
    }
    final file = File(
      p.join(runtimeDir.path, terminalHostHistoryDatabaseFileName),
    );
    final database = sqlite.sqlite3.open(file.path);
    final store = TerminalHostHistoryStore._(file, database);
    store._configure();
    return store;
  }

  final File file;
  final sqlite.Database _database;
  bool _closed = false;

  TerminalHostCheckpoint? read(String sessionId) {
    _requireOpen();
    final rows = _database.select(
      '''
      SELECT sessionId, workspaceId, tabId, workingDirectory, running, exitCode,
             endedAt, updatedAt, buffer
      FROM checkpoints
      WHERE sessionId = ?
      LIMIT 1;
      ''',
      <Object?>[sessionId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return TerminalHostCheckpoint.fromRow(rows.single);
  }

  void upsert(TerminalHostCheckpoint checkpoint) {
    _requireOpen();
    _database.execute(
      '''
      INSERT OR REPLACE INTO checkpoints
        (sessionId, workspaceId, tabId, workingDirectory, running, exitCode,
         endedAt, updatedAt, buffer)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      <Object?>[
        checkpoint.sessionId,
        checkpoint.workspaceId,
        checkpoint.tabId,
        checkpoint.workingDirectory,
        checkpoint.running ? 1 : 0,
        checkpoint.exitCode,
        checkpoint.endedAt?.toUtc().toIso8601String(),
        checkpoint.updatedAt.toUtc().toIso8601String(),
        checkpoint.buffer,
      ],
    );
  }

  void delete(String sessionId) {
    _requireOpen();
    _database.execute('DELETE FROM checkpoints WHERE sessionId = ?;', <Object?>[
      sessionId,
    ]);
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _database.close();
  }

  void _configure() {
    _database
      ..execute('PRAGMA journal_mode = WAL;')
      ..execute('PRAGMA synchronous = NORMAL;')
      ..execute('''
        CREATE TABLE IF NOT EXISTS checkpoints (
          sessionId TEXT PRIMARY KEY,
          workspaceId TEXT NOT NULL,
          tabId TEXT NOT NULL,
          workingDirectory TEXT NOT NULL,
          running INTEGER NOT NULL,
          exitCode INTEGER,
          endedAt TEXT,
          updatedAt TEXT NOT NULL,
          buffer BLOB NOT NULL
        );
      ''');
  }

  void _requireOpen() {
    if (_closed) {
      throw StateError('Terminal host history store is closed.');
    }
  }
}

DateTime? _dateTimeOrNull(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

Uint8List _blob(Object? value) {
  if (value is Uint8List) {
    return Uint8List.fromList(value);
  }
  if (value is List<int>) {
    return Uint8List.fromList(value);
  }
  return Uint8List(0);
}
