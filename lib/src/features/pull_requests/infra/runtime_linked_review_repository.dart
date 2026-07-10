import 'dart:async';

import 'package:alera/src/features/pull_requests/application/linked_review_repository.dart';
import 'package:alera/src/features/pull_requests/domain/linked_review.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

/// [LinkedReviewRepository] over the runtime host RPC. Mirrors
/// `RuntimeProjectConfigRepository`: the host owns the `linkedReviews` table and
/// broadcasts `linkedReviewsChanged` on every mutation.
class RuntimeLinkedReviewRepository implements LinkedReviewRepository {
  RuntimeLinkedReviewRepository(this._client, {this.beforeAccess});

  final RuntimeHostClient _client;
  final Future<void> Function()? beforeAccess;

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
  Stream<LinkedReview?> watch(String workspaceId) async* {
    yield await find(workspaceId);
    await for (final event in _client.runtimeEvents) {
      if (event.name == 'linkedReviewsChanged') {
        yield await find(workspaceId);
      }
    }
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
