import 'dart:async';

import 'package:alera/src/features/orchestration/domain/workflow_cleanup_snapshot.dart';
import 'package:alera/src/features/orchestration/infra/workflow_cleanup_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Mounted-page state only. Durable confirmations and receipts live in Rust.
class WorkflowCleanupSession extends ChangeNotifier {
  WorkflowCleanupSession(
    this.repository,
    this.runId, {
    String? cleanupId,
    String Function()? newId,
  }) : selectedId = cleanupId,
       _newId = newId ?? const Uuid().v4;
  final WorkflowCleanupRepository repository;
  final String runId;
  final String Function() _newId;
  String? selectedId;
  WorkflowCleanupStatus? status;
  List<WorkflowCleanupResource> resources = const [];
  List<WorkflowCleanupSummary> history = const [];
  Map<String, bool> get selection => Map.unmodifiable(_selection);
  final _selection = <String, bool>{};
  int? resourceCursor;
  int? historyCursor;
  int? _resourceRevision;
  int? _historyRevision;
  Object? error;
  bool busy = false;
  bool loading = true;
  bool _disposed = false;
  int _generation = 0;
  (String, Map<String, bool>)? _pendingPreview;
  (WorkflowCleanupPreview, bool)? _pendingApply;
  WorkflowCleanupPreview? _pendingAbandon;
  bool get abandonPending => _pendingAbandon != null;
  bool get previewPending => _pendingPreview != null;
  bool get selectionLocked => busy || previewPending;
  bool get canPrepare =>
      !busy &&
      (previewPending ||
          (error == null &&
              _selection.isNotEmpty &&
              _selection.keys.every(
                (id) => resources.any(
                  (item) => item.identity.id == id && item.canSelect,
                ),
              )));

  void reportError(Object value) {
    if (_disposed) return;
    _generation++;
    error = value;
    loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_disposed || busy) return;
    final generation = ++_generation;
    final id = selectedId;
    try {
      if (id != null) {
        final next = await repository.status(id, runId);
        if (_disposed || generation != _generation) return;
        final pending = _pendingApply;
        if (pending != null && next.preview.digest != pending.$1.digest) {
          throw const FormatException(
            'Cleanup confirmation changed while its response was pending.',
          );
        }
        if (_pendingAbandon != null &&
            next.preview.digest != _pendingAbandon!.digest) {
          throw const FormatException(
            'Cleanup changed while abandonment was pending.',
          );
        }
        status = next;
        if (next.state != WorkflowCleanupState.preview) _pendingApply = null;
        if (next.state == WorkflowCleanupState.abandoned) {
          _pendingAbandon = null;
        }
      } else {
        final pages = await Future.wait<Object>([
          repository.resources(runId),
          repository.history(runId),
        ]);
        if (_disposed || generation != _generation) return;
        final resourcePage =
            pages[0] as WorkflowCleanupPage<WorkflowCleanupResource>;
        final historyPage =
            pages[1] as WorkflowCleanupPage<WorkflowCleanupSummary>;
        resources = resourcePage.items;
        resourceCursor = resourcePage.nextBeforeRow;
        _resourceRevision = resourcePage.revision;
        history = historyPage.items;
        historyCursor = historyPage.nextBeforeRow;
        _historyRevision = historyPage.revision;
      }
      if (_pendingApply == null &&
          _pendingPreview == null &&
          _pendingAbandon == null) {
        error = null;
      }
    } on Object catch (value) {
      if (!_disposed && generation == _generation) error = value;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void select(String id, bool value) {
    if (selectionLocked) return;
    if (value) {
      if (_selection.length >= 25 ||
          !resources.any((item) => item.identity.id == id && item.canSelect)) {
        return;
      }
      _selection.putIfAbsent(id, () => false);
    } else {
      _selection.remove(id);
    }
    notifyListeners();
  }

  void removeBranch(String id, bool value) {
    if (selectionLocked || !_selection.containsKey(id)) return;
    _selection[id] = value;
    notifyListeners();
  }

  void clearSelection() {
    if (busy) return;
    _pendingPreview = null;
    _selection.clear();
    error = null;
    notifyListeners();
  }

  Future<void> open(String? id) async {
    if (busy || _disposed) return;
    _generation++;
    selectedId = id;
    status = null;
    _pendingApply = null;
    _pendingAbandon = null;
    loading = true;
    error = null;
    notifyListeners();
    await refresh();
  }

  Future<void> prepare() async {
    if (!canPrepare || _disposed) return;
    _pendingPreview ??= (_newId(), Map<String, bool>.unmodifiable(_selection));
    final pending = _pendingPreview!;
    await _mutate(() async {
      final preview = await repository.prepare(pending.$1, runId, pending.$2);
      if (_disposed) return;
      status = WorkflowCleanupStatus.forPreview(preview);
      selectedId = preview.id;
      _pendingPreview = null;
    });
  }

  Future<void> apply(bool retry) async {
    if (busy ||
        _disposed ||
        status == null ||
        abandonPending ||
        status!.state == WorkflowCleanupState.abandoned ||
        status!.state == WorkflowCleanupState.retired) {
      return;
    }
    _pendingApply ??= (status!.preview, retry);
    final pending = _pendingApply!;
    await _mutate(() async {
      final result = await repository.apply(pending.$1, retry: pending.$2);
      if (_disposed) return;
      status = result;
      _pendingApply = null;
    });
    if (!_disposed) await refresh();
  }

  Future<void> abandon() async {
    if (busy || _disposed || status?.state != WorkflowCleanupState.attention) {
      return;
    }
    _pendingAbandon ??= status!.preview;
    _pendingApply = null;
    final pending = _pendingAbandon!;
    await _mutate(() async {
      final result = await repository.abandon(pending);
      if (_disposed) return;
      status = result;
      _pendingAbandon = null;
      _selection.clear();
    });
    if (!_disposed) await refresh();
  }

  Future<void> loadMore({required bool operations}) async {
    if (busy || selectedId != null || _disposed) return;
    final cursor = operations ? historyCursor : resourceCursor;
    if (cursor == null) return;
    final generation = _generation + 1;
    await _mutate(() async {
      if (operations) {
        final page = await repository.history(runId, beforeRow: cursor);
        if (_disposed || generation != _generation) return;
        if (page.revision != _historyRevision) {
          throw StateError(
            'Cleanup history changed. Refresh before loading more.',
          );
        }
        history = List.unmodifiable([...history, ...page.items]);
        historyCursor = page.nextBeforeRow;
      } else {
        final page = await repository.resources(runId, beforeRow: cursor);
        if (_disposed || generation != _generation) return;
        if (page.revision != _resourceRevision) {
          throw StateError('Resources changed. Refresh before loading more.');
        }
        resources = List.unmodifiable([...resources, ...page.items]);
        resourceCursor = page.nextBeforeRow;
      }
    });
  }

  Future<void> _mutate(Future<void> Function() operation) async {
    _generation++;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } on Object catch (value) {
      if (!_disposed) error = value;
    } finally {
      if (!_disposed) {
        busy = false;
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
