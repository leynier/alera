part of 'workspace_explorer.dart';

class _PendingExplorerDirectoryReplacement {
  _PendingExplorerDirectoryReplacement({
    required this.generation,
    required this.children,
    required this.waiters,
  });

  final int generation;
  List<native.WorkspaceFileEntry> children;
  final List<Completer<void>> waiters;

  void complete() {
    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }

  void completeError(Object error, StackTrace stackTrace) {
    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(error, stackTrace);
      }
    }
  }
}

class _PendingExplorerWatcherUpdate {
  _PendingExplorerWatcherUpdate({
    required this.generation,
    required this.handle,
    required this.watchedRelativePaths,
    required this.waiters,
  });

  final int generation;
  final native.WorkspaceExplorerWatcherHandle handle;
  List<String> watchedRelativePaths;
  final List<Completer<void>> waiters;

  void complete() {
    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }
}
