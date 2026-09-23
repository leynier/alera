import 'dart:async';

import 'package:alera/src/features/linked_issues/application/linked_issue_repository.dart';
import 'package:alera/src/features/linked_issues/domain/issue_details.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue_link_result.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue_snapshot.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

/// The host runs the forge CLI with a 45 second budget; leave room for the
/// round trip so the host's own timeout is the one the user sees.
const Duration linkedIssueFetchTimeout = Duration(seconds: 60);

/// [LinkedIssueRepository] over the runtime host RPC. The host owns the
/// `linkedIssues` table and broadcasts `linkedIssuesChanged` on every change.
class RuntimeLinkedIssueRepository(
  final RuntimeHostClient _client, {
  final Future<void> Function()? beforeAccess,
  RuntimeChangeCoalescer? coalescer,
}) implements LinkedIssueRepository {
  this : _coalescer = coalescer ?? RuntimeChangeCoalescer();

  final RuntimeChangeCoalescer _coalescer;

  @override
  Future<bool> isSupported() async {
    final client = _client;
    return client is RuntimeHostCapabilityClient &&
        await (client as RuntimeHostCapabilityClient).supportsRuntimeCapability(
          aleraRuntimeHostLinkedIssuesCapability,
        );
  }

  @override
  Stream<LinkedIssueSnapshot> watchSnapshot() {
    return runtimeSnapshotStream(
      client: _client,
      eventNames: const <String>{'linkedIssuesChanged'},
      readSnapshot: () async {
        if (!await isSupported()) {
          return const LinkedIssueSnapshot();
        }
        return LinkedIssueSnapshot(
          supported: true,
          byWorkspace: await listAll(),
        );
      },
      coalesceKey: 'linkedIssues',
      coalescer: _coalescer,
    );
  }

  @override
  Future<Map<String, LinkedIssue>> listAll() async {
    await _ensureReady();
    final payload = _asMap(await _client.runtimeRequest('linkedIssue.list'));
    final items = payload['items'];
    if (items is! List) {
      throw const FormatException('linkedIssue.list must return items.');
    }
    final issues = <String, LinkedIssue>{};
    for (final item in items) {
      final issue = LinkedIssue.fromJson(_asMap(item));
      issues[issue.workspaceId] = issue;
    }
    return issues;
  }

  @override
  Future<LinkedIssueLinkResult> link(String workspaceId, String url) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'linkedIssue.link',
      <String, Object?>{'workspaceId': workspaceId, 'url': url},
      linkedIssueFetchTimeout,
    );
    return LinkedIssueLinkResult.fromJson(_asMap(payload));
  }

  @override
  Future<LinkedIssueLinkResult> refresh(String workspaceId) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'linkedIssue.refresh',
      <String, Object?>{'workspaceId': workspaceId},
      linkedIssueFetchTimeout,
    );
    return LinkedIssueLinkResult.fromJson(_asMap(payload));
  }

  @override
  Future<void> unlink(String workspaceId) async {
    await _ensureReady();
    await _client.runtimeRequest('linkedIssue.remove', <String, Object?>{
      'workspaceId': workspaceId,
    });
  }

  @override
  Future<IssueDetails> fetch(String url) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'issue.fetch',
      <String, Object?>{'url': url},
      linkedIssueFetchTimeout,
    );
    return IssueDetails.fromJson(_asMap(payload));
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
    'Runtime linked issue payload must be a JSON object.',
  );
}
