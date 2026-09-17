import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_pull_request_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_pull_request_summaries_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'loads one summary per workspace when the host supports the verb',
    () async {
      final client = _FakeSummariesClient();
      final container = _container(client);

      final summaries = await container.read(
        workspacePullRequestSummariesControllerProvider('host-1').future,
      );

      expect(summaries.keys, containsAll(<String>['ws-1', 'ws-2']));
      expect(client.requestCount, 1);
    },
  );

  test('answers empty on hosts without the capability', () async {
    final client = _FakeSummariesClient()..supported = false;
    final container = _container(client);

    final summaries = await container.read(
      workspacePullRequestSummariesControllerProvider('host-1').future,
    );

    expect(summaries, isEmpty);
    expect(client.requestCount, 0);
  });

  test('refreshes on workspace and linked review events', () async {
    final client = _FakeSummariesClient();
    final container = _container(client);
    await container.read(
      workspacePullRequestSummariesControllerProvider('host-1').future,
    );

    client
      ..summaries = <String, MobileWorkspacePullRequestSummary>{}
      ..emit('linkedReviewsChanged');
    await Future.pause(Duration.zero);
    await container.read(
      workspacePullRequestSummariesControllerProvider('host-1').future,
    );
    expect(client.requestCount, 2);

    client.emit('workspacesChanged');
    await Future.pause(Duration.zero);
    await container.read(
      workspacePullRequestSummariesControllerProvider('host-1').future,
    );
    expect(client.requestCount, 3);
  });

  test('a failed refresh keeps the last snapshot', () async {
    final client = _FakeSummariesClient();
    final container = _container(client);
    await container.read(
      workspacePullRequestSummariesControllerProvider('host-1').future,
    );

    client.error = StateError('host unreachable');
    client.emit('workspacesChanged');
    await Future.pause(Duration.zero);
    final summaries = await container.read(
      workspacePullRequestSummariesControllerProvider('host-1').future,
    );

    expect(summaries.keys, containsAll(<String>['ws-1', 'ws-2']));
    expect(client.requestCount, 2);
  });
}

ProviderContainer _container(_FakeSummariesClient client) {
  final container = ProviderContainer(
    overrides: [
      workspaceClientProvider('host-1').overrideWith((ref) async => client),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.dispose);
  final subscription = container.listen(
    workspacePullRequestSummariesControllerProvider('host-1'),
    (_, _) {},
  );
  addTearDown(subscription.close);
  return container;
}

class _FakeSummariesClient
    implements
        MobileWorkspaceClient,
        MobileWorkspacePullRequestSummariesClient {
  final StreamController<MobileRuntimeEvent> _events =
      StreamController<MobileRuntimeEvent>.broadcast();

  bool supported = true;
  Object? error;
  int requestCount = 0;
  Map<String, MobileWorkspacePullRequestSummary>
  summaries = <String, MobileWorkspacePullRequestSummary>{
    'ws-1': MobileWorkspacePullRequestSummary(workspaceId: 'ws-1', number: 1),
    'ws-2': MobileWorkspacePullRequestSummary(workspaceId: 'ws-2', number: 2),
  };

  void emit(String name) {
    _events.add(MobileRuntimeEvent(name, const <String, Object?>{}));
  }

  Future<void> dispose() => _events.close();

  @override
  Stream<MobileRuntimeEvent> get events => _events.stream;

  @override
  bool get supportsPullRequestSummaries => supported;

  @override
  Future<Map<String, MobileWorkspacePullRequestSummary>>
  pullRequestSummaries() async {
    requestCount += 1;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return summaries;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
