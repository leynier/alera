import 'dart:async';

import 'package:alera/src/features/workbench/application/source_control_watcher.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;

/// In-memory [SourceControlWatcher] for tests: lets a test drive watch signals
/// without touching the filesystem or the native bridge.
class FakeSourceControlWatcher extends SourceControlWatcher {
  FakeSourceControlWatcher();

  final StreamController<native.SourceControlWatchSignal> _signals =
      StreamController<native.SourceControlWatchSignal>.broadcast();

  int startCount = 0;
  int stopCount = 0;

  /// Emits a watch signal, mimicking an external file or `.git/` change.
  void emitChange({int coalescedEventCount = 1}) {
    _signals.add(
      native.SourceControlWatchSignal(coalescedEventCount: coalescedEventCount),
    );
  }

  @override
  Future<native.SourceControlWatcherHandle> start({
    required String workspacePath,
  }) async {
    startCount += 1;
    return const native.SourceControlWatcherHandle(id: 'fake');
  }

  @override
  Stream<native.SourceControlWatchSignal> events({
    required native.SourceControlWatcherHandle handle,
  }) {
    return _signals.stream;
  }

  @override
  Future<void> stop({
    required native.SourceControlWatcherHandle handle,
  }) async {
    stopCount += 1;
  }

  Future<void> dispose() => _signals.close();
}
