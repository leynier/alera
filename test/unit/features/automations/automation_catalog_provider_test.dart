import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/infra/runtime_automation_repository.dart';
import 'package:alera/src/features/automations/presentation/automation_actions.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/automation_test_harness.dart';

void main() {
  late FakeAutomationRuntime runtime;
  late ProviderContainer container;

  setUp(() {
    runtime = FakeAutomationRuntime()
      ..automations = <Map<String, Object?>>[automationJson()];
    container = automationContainer(runtime);
  });

  tearDown(() async {
    container.dispose();
    await runtime.dispose();
  });

  Future<void> settle() => Future.pause(const Duration(milliseconds: 20));

  test('the catalog reloads on lifecycle events and on reconnection', () async {
    final subscription = container.listen(automationCatalogProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(automationCatalogProvider.future);
    expect(runtime.requestsOf('automation.list'), hasLength(1));
    expect(
      runtime.requestsOf('automation.list').single.payload['includeTrashed'],
      isTrue,
    );
    for (final event in <String>[
      'automationsChanged',
      'automationRunChanged',
      'automationAttentionRequired',
      aleraRuntimeHostConnectedEvent,
    ]) {
      runtime.emit(event);
      await settle();
      await container.read(automationCatalogProvider.future);
    }
    expect(runtime.requestsOf('automation.list'), hasLength(5));
  });

  test('a detail reloads only for its own automation', () async {
    final provider = automationDetailControllerProvider('nightly');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    runtime.emit('automationRunChanged', {'automationId': 'other'});
    await settle();
    expect(runtime.requestsOf('automation.show'), hasLength(1));
    runtime.emit('automationRunChanged', {'automationId': 'nightly'});
    await settle();
    await container.read(provider.future);
    expect(runtime.requestsOf('automation.show'), hasLength(2));
  });

  test('Run Now sends no overrides so the definition decides', () async {
    final repository = container.read(automationRepositoryProvider);
    await repository.runNow('nightly');
    final payload = runtime.requestsOf('automation.runNow').single.payload;
    expect(payload, <String, Object?>{'id': 'nightly'});
    await repository.runNow('nightly', continueFromRunId: 'run-1');
    expect(
      runtime.requestsOf('automation.runNow').last.payload['continueFromRunId'],
      'run-1',
    );
  });

  test('Run Now feedback follows the status the runtime returned', () {
    String message(String status) => automationRunNowFeedback(
      AutomationRunRecord.fromJson(<String, Object?>{
        'number': 4,
        'status': status,
      }),
    ).$1;
    expect(message('dispatching'), 'Run #4 started.');
    expect(message('overlapSkipped'), contains('previous run is still active'));
    expect(message('precheckSkipped'), contains('precheck skipped'));
    expect(
      automationRunNowFeedback(
        AutomationRunRecord.fromJson(<String, Object?>{'status': 'blocked'}),
      ).$2,
      AleraToastTone.error,
    );
  });

  test(
    'authoring uses the additive create RPC; older runtimes the upsert',
    () async {
      final repository = container.read(automationRepositoryProvider);
      final created = await repository.create(
        <String, Object?>{'name': 'Nightly', 'promptTemplate': 'Review'},
        authoring: true,
        requestKey: 'key-1',
      );
      expect(created.state, 'active');
      expect(
        runtime.requestsOf('automation.create').single.payload['requestKey'],
        'key-1',
      );
      await repository.create(<String, Object?>{
        'name': 'Nightly Review',
        'promptTemplate': 'Review',
      }, authoring: false);
      final legacy =
          runtime.requestsOf('automation.upsert').single.payload['automation']!
              as Map<String, Object?>;
      expect(legacy['slug'], 'nightly-review');
      expect(legacy['id'], isNotEmpty);
      expect(legacy['state'], 'active');
    },
  );

  test('a rejected create surfaces the runtime readiness', () async {
    final rejecting = _RejectingRuntime();
    addTearDown(rejecting.dispose);
    final repository = RuntimeAutomationRepository(rejecting);
    await expectLater(
      repository.create(const <String, Object?>{}, authoring: true),
      throwsA(
        isA<AutomationReadinessException>().having(
          (error) => error.readiness.errors.single.field,
          'field',
          'target',
        ),
      ),
    );
  });

  test('capabilities come from the runtime', () async {
    runtime.capabilities = <String>{automationsAuthoringCapability};
    final capabilities = await container.read(
      automationRuntimeCapabilitiesProvider.future,
    );
    expect(capabilities.authoring, isTrue);
    expect(capabilities.observe, isFalse);
  });

  test('takeOver sends only the run id', () async {
    await container.read(automationRepositoryProvider).takeOver('run-9');
    expect(
      runtime.requestsOf('automation.takeOver').single.payload,
      <String, Object?>{'runId': 'run-9'},
    );
  });
}

class _RejectingRuntime extends FakeAutomationRuntime {
  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async => <String, Object?>{
    'readiness': <String, Object?>{
      'ready': false,
      'issues': <Object?>[
        <String, Object?>{
          'code': 'targetMissing',
          'message': 'Choose a target.',
          'field': 'target',
          'severity': 'error',
        },
      ],
    },
  };
}
