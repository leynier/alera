import 'dart:async';

import 'package:alera/src/features/orchestration/domain/run_execution_policy.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class RuntimeRunPolicyRepository {
  RuntimeRunPolicyRepository(this._client, {this.beforeAccess});

  final RuntimeHostClient _client;
  final Future<void> Function()? beforeAccess;

  /// Runs the app can review, newest first. Only runs that actually carry a
  /// plan are returned: a run without one needs no decision.
  Future<List<RunExecutionPolicy>> listPolicies() async {
    await beforeAccess?.call();
    final payload = await _client.runtimeRequest('orchestration.runList');
    final runs = payload is Map ? payload['items'] : null;
    if (runs is! List) {
      return const <RunExecutionPolicy>[];
    }
    final policies = <RunExecutionPolicy>[];
    for (final run in runs) {
      if (run is! Map) {
        continue;
      }
      final runId = run['id'];
      if (runId is! String || runId.isEmpty) {
        continue;
      }
      final policy = await showPolicy(runId);
      if (policy.hasPolicy) {
        policies.add(policy);
      }
    }
    return policies;
  }

  Future<RunExecutionPolicy> showPolicy(String runId) async {
    await beforeAccess?.call();
    final payload = await _client.runtimeRequest(
      'orchestration.runPolicyShow',
      <String, Object?>{'run': runId},
    );
    return RunExecutionPolicy.fromJson(_mapFromPayload(payload));
  }

  Future<RunExecutionPolicy> approve(String runId) async {
    await beforeAccess?.call();
    final payload = await _client.runtimeRequest(
      'orchestration.runPolicyApprove',
      <String, Object?>{'run': runId, 'actor': 'app'},
    );
    return RunExecutionPolicy.fromJson(_mapFromPayload(payload));
  }

  Future<RunExecutionPolicy> reject(String runId, String reason) async {
    await beforeAccess?.call();
    final payload = await _client.runtimeRequest(
      'orchestration.runPolicyReject',
      <String, Object?>{'run': runId, 'reason': reason, 'actor': 'app'},
    );
    return RunExecutionPolicy.fromJson(_mapFromPayload(payload));
  }
}

Map<String, Object?> _mapFromPayload(Object? payload) {
  if (payload is Map) {
    return Map<String, Object?>.from(payload);
  }
  throw const FormatException(
    'Runtime run policy payload must be a JSON object.',
  );
}
