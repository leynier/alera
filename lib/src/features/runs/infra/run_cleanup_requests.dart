import 'dart:convert';

import 'package:alera/src/features/runs/domain/run_cleanup.dart';
import 'package:flutter/foundation.dart';

/// The cleanup verbs of `runs.*`. Responses carry filesystem path
/// projections, so they are decoded off the UI isolate, and every receipt is
/// checked against the preview the user reviewed.
mixin RunCleanupRequests {
  Future<Map<String, Object?>> request(
    String verb,
    Map<String, Object?> payload, {
    Duration? timeout,
  });

  Future<RunCleanupPage<RunCleanupResource>> resources(
    String runId, {
    int? beforeRow,
  }) async {
    final page = await compute(
      _resources,
      await request('runs.resources', <String, Object?>{
        'runId': runId,
        'beforeRow': ?beforeRow,
      }),
    );
    page.requireRun(runId);
    if (page.items.any((item) => item.identity.runId != runId)) {
      throw const FormatException('Cleanup resource belongs to another run.');
    }
    return page;
  }

  Future<RunCleanupPage<RunCleanupHistoryItem>> cleanups(
    String runId, {
    int? beforeRow,
  }) async {
    final page = await compute(
      _history,
      await request('runs.cleanups', <String, Object?>{
        'runId': runId,
        'beforeRow': ?beforeRow,
      }),
    );
    page.requireRun(runId);
    return page;
  }

  Future<RunCleanupPreview> previewCleanup(
    String id,
    String runId,
    Map<String, bool> resources,
  ) async {
    final selected = Map<String, bool>.unmodifiable(resources);
    if (selected.isEmpty || selected.length > runCleanupSelectionLimit) {
      throw const FormatException('Select between one and 25 resources.');
    }
    final payload = <String, Object?>{
      'id': id,
      'runId': runId,
      'resources': <Object?>[
        for (final item in selected.entries)
          <String, Object?>{
            'workspaceId': item.key,
            'removeBranch': item.value,
          },
      ],
    };
    if (utf8.encode(jsonEncode(payload)).length > 8192) {
      throw const FormatException('Cleanup selection is too large.');
    }
    final preview = await compute(
      _preview,
      await request(
        'runs.previewCleanup',
        payload,
        timeout: const Duration(seconds: 30),
      ),
    );
    preview.requireIdentity(id, runId);
    if (preview.items.length != selected.length ||
        preview.items.any(
          (item) => selected[item.identity.id] != item.removeBranch,
        )) {
      throw const FormatException(
        'Cleanup preview changed the selected resources or branches.',
      );
    }
    return preview;
  }

  Future<RunCleanupStatus> cleanupStatus(String id, String runId) async {
    final status = await compute(
      _status,
      await request('runs.cleanup', <String, Object?>{'id': id}),
    );
    status.preview.requireIdentity(id, runId);
    return status;
  }

  Future<RunCleanupStatus> applyCleanup(
    RunCleanupPreview preview, {
    bool retry = false,
  }) async {
    final status = await compute(
      _status,
      await request(
        retry ? 'runs.retryCleanup' : 'runs.applyCleanup',
        <String, Object?>{
          'id': preview.id,
          'digest': preview.digest,
          if (!retry) 'confirm': true,
        },
        timeout: const Duration(seconds: 30),
      ),
    );
    status.preview.requireIdentity(preview.id, preview.runId);
    if (status.preview.digest != preview.digest) {
      throw const FormatException(
        'Cleanup receipt changed the reviewed digest.',
      );
    }
    return status;
  }

  Future<RunCleanupStatus> abandonCleanup(RunCleanupPreview preview) async {
    final status = await compute(
      _status,
      await request('runs.abandonCleanup', <String, Object?>{
        'id': preview.id,
        'digest': preview.digest,
      }, timeout: const Duration(seconds: 30)),
    );
    status.preview.requireIdentity(preview.id, preview.runId);
    if (status.preview.digest != preview.digest ||
        status.state != RunCleanupState.abandoned) {
      throw const FormatException(
        'Cleanup abandonment receipt changed the reviewed operation.',
      );
    }
    return status;
  }
}

RunCleanupPage<RunCleanupResource> _resources(Map<String, Object?> json) =>
    RunCleanupPage.fromJson(json, RunCleanupResource.fromJson);
RunCleanupPage<RunCleanupHistoryItem> _history(Map<String, Object?> json) =>
    RunCleanupPage.fromJson(json, RunCleanupHistoryItem.fromJson);
RunCleanupPreview _preview(Map<String, Object?> json) =>
    RunCleanupPreview.fromJson(json);
RunCleanupStatus _status(Map<String, Object?> json) =>
    RunCleanupStatus.fromJson(json);
