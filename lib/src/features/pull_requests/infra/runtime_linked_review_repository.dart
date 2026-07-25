import 'dart:async';

import 'package:alera/src/features/pull_requests/application/linked_review_repository.dart';
import 'package:alera/src/features/pull_requests/domain/linked_review.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

/// [LinkedReviewRepository] over the runtime host RPC. Mirrors
/// `RuntimeProjectConfigRepository`: the host owns the `linkedReviews` table and
/// broadcasts `linkedReviewsChanged` on every mutation.
class RuntimeLinkedReviewRepository implements LinkedReviewRepository {
  RuntimeLinkedReviewRepository(
    this._client, {
    this.beforeAccess,
    RuntimeChangeCoalescer? coalescer,
  }) : _coalescer = coalescer ?? RuntimeChangeCoalescer();

  final RuntimeHostClient _client;
  final Future<void> Function()? beforeAccess;
  final RuntimeChangeCoalescer _coalescer;

  @override
  Future<LinkedReview?> find(String workspaceId) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'linkedReview.find',
      <String, Object?>{'workspaceId': workspaceId},
    );
    if (payload == null) {
      return null;
    }
    return LinkedReview.fromJson(_asMap(payload));
  }

  @override
  Stream<LinkedReview?> watch(String workspaceId) {
    return runtimeSnapshotStream(
      client: _client,
      eventNames: const <String>{'linkedReviewsChanged'},
      readSnapshot: () => find(workspaceId),
      coalesceKey: 'linkedReview:$workspaceId',
      coalescer: _coalescer,
      matchesScope: runtimeScopeMatcher('workspaceId', workspaceId),
    );
  }

  @override
  Future<void> save(LinkedReview review) async {
    await _ensureReady();
    await _client.runtimeRequest('linkedReview.upsert', review.toMap());
  }

  @override
  Future<void> remove(String workspaceId) async {
    await _ensureReady();
    await _client.runtimeRequest('linkedReview.remove', <String, Object?>{
      'workspaceId': workspaceId,
    });
  }

  Future<void> _ensureReady() async {
    final callback = beforeAccess;
    if (callback != null) {
      await callback();
    }
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw const FormatException(
    'Runtime linked review payload must be a JSON object.',
  );
}
