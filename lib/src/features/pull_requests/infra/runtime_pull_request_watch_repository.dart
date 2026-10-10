import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

/// Runtime capability for Watch and Fix execution on every forge the runtime
/// supports (GitHub, GitLab, and Azure DevOps).
const pullRequestWatchExecutionV2Capability = 'pullRequestWatchExecutionV2';

/// Runtime capability for `pullRequest.agentDispatch`, the single source of
/// the Restack and Fix Failed Checks prompts.
const pullRequestAgentDispatchCapability = 'pullRequestAgentDispatchV1';

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

  /// Whether the runtime runs Watch and Fix for [provider], so this client
  /// MUST NOT also evaluate, dispatch, or merge it. `pullRequestWatchExecutionV2`
  /// covers GitHub, GitLab, and Azure DevOps; `pullRequestWatchExecutionV1`
  /// covers GitHub only.
  Future<bool> ownsExecutionFor(GitHostingProvider? provider) async {
    final client = _client;
    if (provider == null || client is! RuntimeHostCapabilityClient) {
      return false;
    }
    final capabilities = client as RuntimeHostCapabilityClient;
    if (await capabilities.supportsRuntimeCapability(
      pullRequestWatchExecutionV2Capability,
    )) {
      return true;
    }
    return provider == GitHostingProvider.github &&
        await capabilities.supportsRuntimeCapability(
          'pullRequestWatchExecutionV1',
        );
  }

  /// The Restack (`restack`) or Fix Failed Checks (`fixFailedChecks`) prompt
  /// from the runtime, which owns their text when it advertises
  /// `pullRequestAgentDispatchV1`. Null on an older runtime or a failed read,
  /// so the caller falls back to its bundled prompt.
  Future<String?> agentDispatchPrompt({
    required String workspaceId,
    required String kind,
    int? reviewNumber,
  }) async {
    final client = _client;
    if (client is! RuntimeHostCapabilityClient ||
        !await (client as RuntimeHostCapabilityClient)
            .supportsRuntimeCapability(pullRequestAgentDispatchCapability)) {
      return null;
    }
    try {
      final payload = _asMap(
        await _client.runtimeRequest(
          'pullRequest.agentDispatch',
          <String, Object?>{
            'workspaceId': workspaceId,
            'kind': kind,
            'number': ?reviewNumber,
          },
        ),
      );
      final prompt = payload['prompt'];
      return prompt is String && prompt.trim().isNotEmpty ? prompt : null;
    } on Object {
      return null;
    }
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
