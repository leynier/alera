import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

class RuntimePullRequestWatchRepository {
  RuntimePullRequestWatchRepository(
    this._client, {
    RuntimeChangeCoalescer? coalescer,
  }) : _coalescer = coalescer ?? RuntimeChangeCoalescer();

  final RuntimeHostClient _client;
  final RuntimeChangeCoalescer _coalescer;

  Future<bool> supportsExecution() async {
    final client = _client;
    return client is RuntimeHostCapabilityClient &&
        await (client as RuntimeHostCapabilityClient).supportsRuntimeCapability(
          'pullRequestWatchExecutionV1',
        );
  }

  Future<bool> isSupported() async {
    final client = _client;
    return client is RuntimeHostCapabilityClient &&
        await (client as RuntimeHostCapabilityClient).supportsRuntimeCapability(
          aleraRuntimeHostPullRequestWatchCapability,
        );
  }

  Stream<PullRequestAgentWatchRecords> watchSnapshot() {
    return runtimeSnapshotStream(
      client: _client,
      eventNames: const <String>{'pullRequestWatchChanged'},
      readSnapshot: () async {
        if (!await isSupported()) {
          return const PullRequestAgentWatchRecords();
        }
        return PullRequestAgentWatchRecords(
          supported: true,
          byWorkspace: await listAll(),
        );
      },
      coalesceKey: 'pullRequestWatch',
      coalescer: _coalescer,
    );
  }

  Future<Map<String, PullRequestAgentWatchRecord>> listAll() async {
    final payload = _asMap(
      await _client.runtimeRequest('pullRequestWatch.list'),
    );
    final items = payload['items'];
    if (items is! List) {
      throw const FormatException('pullRequestWatch.list must return items.');
    }
    final watches = <String, PullRequestAgentWatchRecord>{};
    for (final item in items) {
      final record = PullRequestAgentWatchRecord.fromJson(_asMap(item));
      if (record.workspaceId.isEmpty) {
        continue;
      }
      watches[record.workspaceId] = record;
    }
    return watches;
  }

  Future<PullRequestAgentWatchRecord> upsert(
    PullRequestAgentWatchRecord record,
  ) async {
    final payload = await _client.runtimeRequest(
      'pullRequestWatch.start',
      record.toJson(),
    );
    return PullRequestAgentWatchRecord.fromJson(_asMap(payload));
  }

  Future<void> remove(String workspaceId) async {
    await _client.runtimeRequest('pullRequestWatch.stop', <String, Object?>{
      'workspaceId': workspaceId,
    });
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
    'Runtime pull request watch payload must be a JSON object.',
  );
}
