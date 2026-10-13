import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'source_control_watcher.g.dart';

/// Thin, injectable wrapper over the native recursive source-control watcher.
///
/// The watcher observes the working tree and its actual Git directories, ignores
/// file access, and classifies coalesced changes for selective queries. Tests override [sourceControlWatcherProvider] with a fake.
class const SourceControlWatcher() {
  Future<native.SourceControlWatcherHandle> start({
    required String workspacePath,
  }) {
    return native.startSourceControlWatcher(workspacePath: workspacePath);
  }

  Stream<native.SourceControlWatchSignal> events({
    required native.SourceControlWatcherHandle handle,
  }) {
    return native.watchSourceControlEvents(handle: handle);
  }

  Future<void> stop({required native.SourceControlWatcherHandle handle}) {
    return native.stopSourceControlWatcher(handle: handle);
  }
}

@Riverpod(keepAlive: true)
SourceControlWatcher sourceControlWatcher(Ref ref) {
  return const SourceControlWatcher();
}
