import 'package:alera_mobile/src/features/pull_requests/infra/mobile_runtime_pull_request_watch_requests.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime watch execution covers V1 and V2 runtimes', () {
    expect(
      _Requests(<String>{'pullRequestWatchExecutionV1'})
          .supportsPullRequestWatchExecution,
      isTrue,
    );
    expect(
      _Requests(<String>{'pullRequestWatchExecutionV2'})
          .supportsPullRequestWatchExecution,
      isTrue,
    );
    expect(_Requests(<String>{}).supportsPullRequestWatchExecution, isFalse);
  });

  test('agent prompts come from runtimes that own them', () async {
    final runtime = _Requests(<String>{'pullRequestAgentDispatchV1'});
    final prompt = await runtime.pullRequestAgentPrompt(
      workspaceId: 'w',
      kind: 'fixFailedChecks',
      reviewNumber: 9,
    );
    expect(prompt, 'Pull request #9 checks failed. Please fix them.');
    expect(runtime.payloads.single, <String, Object?>{
      'workspaceId': 'w',
      'kind': 'fixFailedChecks',
      'number': 9,
    });
    final older = _Requests(<String>{});
    expect(
      await older.pullRequestAgentPrompt(workspaceId: 'w', kind: 'restack'),
      isNull,
    );
    expect(older.payloads, isEmpty);
  });
}

class _Requests with MobileRuntimePullRequestWatchRequests {
  _Requests(this.runtimeCapabilities);

  @override
  final Set<String> runtimeCapabilities;
  final payloads = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    expect(type, 'pullRequest.agentDispatch');
    payloads.add(payload);
    return <String, Object?>{
      'prompt':
          'Pull request #${payload['number']} checks failed. Please fix them.',
    };
  }
}
