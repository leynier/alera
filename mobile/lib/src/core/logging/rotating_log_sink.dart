import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Default ceiling per file, and how many files are kept.
///
/// Rotation is by size rather than by date so the disk cost stays predictable:
/// a quiet week and a crash loop both stay inside the same bound. The caps are
/// lower than the desktop's because phone storage is scarcer and a companion
/// app produces far less output than a host running terminals.
const int kDefaultLogMaxBytes = 2 * 1024 * 1024;
const int kDefaultLogMaxFiles = 3;

/// Appends lines to a size-bounded file with a fixed number of backups.
///
/// Writes are chained rather than awaited by callers so logging never blocks
/// the frame pipeline. The chain also serializes rotation against in-flight
/// writes, which would otherwise race over the file handle.
class RotatingLogSink {
  RotatingLogSink({
    required this.directory,
    required this.baseName,
    this.maxBytes = kDefaultLogMaxBytes,
    this.maxFiles = kDefaultLogMaxFiles,
  });

  final Directory directory;
  final String baseName;
  final int maxBytes;
  final int maxFiles;

  IOSink? _sink;
  int _written = 0;
  Future<void> _queue = Future<void>.value();
  bool _closed = false;

  /// Path of the active file (index 0) or of one of its backups.
  File fileFor(int index) {
    final name = index == 0 ? '$baseName.log' : '$baseName.$index.log';
    return File(p.join(directory.path, name));
  }

  /// Queues [line] for writing. The returned future completes once this line
  /// has been handed to the file, but callers are free to ignore it.
  Future<void> writeLine(String line) {
    if (_closed) {
      return Future<void>.value();
    }
    _queue = _queue.then((_) => _writeLine(line)).catchError((Object _) {
      // A logging failure must stay silent: reporting it through the logger
      // would recurse straight back into this sink.
    });
    return _queue;
  }

  Future<void> _writeLine(String line) async {
    final bytes = utf8.encode(line).length + 1;
    await _ensureOpen();
    // Rotating only when something is already written keeps a single record
    // larger than the cap from producing an endless run of empty files.
    if (_written > 0 && _written + bytes > maxBytes) {
      await _rotate();
    }
    _sink?.writeln(line);
    _written += bytes;
  }

  Future<void> _ensureOpen() async {
    if (_sink != null) {
      return;
    }
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    final active = fileFor(0);
    _written = active.existsSync() ? await active.length() : 0;
    _sink = active.openWrite(mode: FileMode.append);
  }

  Future<void> _rotate() async {
    // Close before renaming: Windows refuses to rename an open file.
    await _closeSink();
    _written = 0;

    if (maxFiles <= 1) {
      final active = fileFor(0);
      if (active.existsSync()) {
        await active.delete();
      }
      await _ensureOpen();
      return;
    }

    final oldest = fileFor(maxFiles - 1);
    if (oldest.existsSync()) {
      await oldest.delete();
    }
    for (var index = maxFiles - 2; index >= 1; index--) {
      final from = fileFor(index);
      if (from.existsSync()) {
        await from.rename(fileFor(index + 1).path);
      }
    }
    final active = fileFor(0);
    if (active.existsSync()) {
      await active.rename(fileFor(1).path);
    }
    await _ensureOpen();
  }

  Future<void> _closeSink() async {
    final sink = _sink;
    _sink = null;
    if (sink == null) {
      return;
    }
    await sink.flush();
    await sink.close();
  }

  /// Waits for queued writes to reach the file.
  Future<void> flush() async {
    await _queue;
    await _sink?.flush();
  }

  Future<void> close() async {
    _closed = true;
    await _queue;
    await _closeSink();
  }

  /// Existing log files, newest first, for collection into a bundle.
  List<File> existingFiles() {
    return <File>[
      for (var index = 0; index < maxFiles; index++) fileFor(index),
    ].where((file) => file.existsSync()).toList();
  }
}
