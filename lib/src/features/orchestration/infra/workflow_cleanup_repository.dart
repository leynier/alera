import 'dart:convert';

import 'package:alera/src/features/orchestration/domain/workflow_cleanup_snapshot.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:flutter/foundation.dart';

class WorkflowCleanupRepository {
  WorkflowCleanupRepository(this.lifecycle);
  final WorkflowLifecycleRepository lifecycle;

  Future<WorkflowCleanupPage<WorkflowCleanupResource>> resources(
    String runId, {
    int? beforeRow,
  }) async {
    final page = await compute(
      _resources,
      await lifecycle.request('workflows.cleanupResources', {
        'runId': runId,
        'beforeRow': beforeRow,
      }),
    );
    page.requireRun(runId);
    if (page.items.any((item) => item.identity.runId != runId)) {
      throw const FormatException('Cleanup resource belongs to another run.');
    }
    return page;
  }

  Future<WorkflowCleanupPage<WorkflowCleanupSummary>> history(
    String runId, {
    int? beforeRow,
  }) async {
    final page = await compute(
      _history,
      await lifecycle.request('workflows.cleanups', {
        'runId': runId,
        'beforeRow': beforeRow,
      }),
    );
    page.requireRun(runId);
    return page;
  }

  Future<WorkflowCleanupPreview> prepare(
    String id,
    String runId,
    Map<String, bool> resources,
  ) async {
    final selected = Map<String, bool>.unmodifiable(resources);
    if (selected.isEmpty || selected.length > 25) {
      throw const FormatException('Select between one and 25 resources.');
    }
    // Only up to 25 scalar IDs/flags, capped below at 8 KiB. Large response
    // documents and filesystem path projections are decoded off the UI isolate.
    final document = jsonEncode({
      'id': id,
      'runId': runId,
      'resources': [
        for (final item in selected.entries)
          {'workspaceId': item.key, 'removeBranch': item.value},
      ],
    });
    if (utf8.encode(document).length > 8192) {
      throw const FormatException('Cleanup selection is too large.');
    }
    final preview = await compute(
      _preview,
      await lifecycle.request('workflows.previewCleanup', {
        'document': document,
      }),
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

  Future<WorkflowCleanupStatus> status(String id, String runId) async {
    final status = await compute(
      _status,
      await lifecycle.request('workflows.cleanupStatus', {'id': id}),
    );
    status.preview.requireIdentity(id, runId);
    return status;
  }

  Future<WorkflowCleanupStatus> apply(
    WorkflowCleanupPreview preview, {
    bool retry = false,
  }) async {
    final status = await compute(
      _status,
      await lifecycle.request(
        retry ? 'workflows.retryCleanup' : 'workflows.applyCleanup',
        {'id': preview.id, 'digest': preview.digest},
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
}

WorkflowCleanupPage<WorkflowCleanupResource> _resources(
  Map<String, Object?> json,
) => WorkflowCleanupPage.fromJson(json, WorkflowCleanupResource.fromJson);
WorkflowCleanupPage<WorkflowCleanupSummary> _history(
  Map<String, Object?> json,
) => WorkflowCleanupPage.fromJson(json, WorkflowCleanupSummary.fromJson);
WorkflowCleanupPreview _preview(Map<String, Object?> json) =>
    WorkflowCleanupPreview.fromJson(json);
WorkflowCleanupStatus _status(Map<String, Object?> json) =>
    WorkflowCleanupStatus.fromJson(json);
