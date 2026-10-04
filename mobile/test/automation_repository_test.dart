import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_automation_client.dart';

void main() {
  test('creates through the authoring RPC without approval fields', () async {
    final client = FakeAutomationClient();
    addTearDown(client.dispose);
    final repository = MobileRuntimeAutomationRepository(client);
    final created = await repository.create(<String, Object?>{
      'name': 'Nightly',
      'promptTemplate': 'Review',
    }, requestKey: 'key');
    expect(created.id, 'created');
    final payload = client.callsOf('automation.create').single.payload;
    expect(payload['requestKey'], 'key');
    expect(client.callsOf('automation.upsert'), isEmpty);
  });

  test('older runtimes get a complete upsert definition', () async {
    final client = FakeAutomationClient(
      capabilities: <String>{'automationsV1'},
    );
    addTearDown(client.dispose);
    await MobileRuntimeAutomationRepository(client).create(<String, Object?>{
      'name': 'Nightly Review',
      'promptTemplate': 'Review',
    });
    final sent =
        client.callsOf('automation.upsert').single.payload['automation']!
            as Map<String, Object?>;
    expect(sent['slug'], 'nightly-review');
    expect(sent['state'], 'active');
  });

  test('Run Now leaves precheck and overlap to the definition', () async {
    final client = FakeAutomationClient();
    addTearDown(client.dispose);
    await MobileRuntimeAutomationRepository(client).runNow('nightly');
    expect(
      client.callsOf('automation.runNow').single.payload,
      <String, Object?>{'id': 'nightly'},
    );
  });

  test(
    'the catalog reloads on automation events from the paired runtime',
    () async {
      final client = FakeAutomationClient();
      addTearDown(client.dispose);
      final container = ProviderContainer(
        overrides: [
          mobileAutomationClientProvider('host')
              .overrideWith((ref) async => client),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        mobileAutomationCatalogProvider('host'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(mobileAutomationCatalogProvider('host').future);
      client.emit('automationRunChanged', {'automationId': 'nightly'});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await container.read(mobileAutomationCatalogProvider('host').future);
      client.emit('unrelatedEvent');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(client.callsOf('automation.list'), hasLength(2));
    },
  );

  test('observation is detected from the runtime capabilities', () {
    final client = FakeAutomationClient(
      capabilities: <String>{'automationsV1', automationsAuthoringCapability},
    );
    addTearDown(client.dispose);
    final repository = MobileRuntimeAutomationRepository(client);
    expect(repository.supportsAuthoring, isTrue);
    expect(repository.supportsObserve, isFalse);
  });

  test('a taken-over tab is no longer observed', () {
    const payload = <String, Object?>{'automationOwned': true};
    expect(mobileAutomationTabIsObserved(payload, 'tab', const {}), isTrue);
    expect(
      mobileAutomationTabIsObserved(payload, 'tab', const {'tab'}),
      isFalse,
    );
    expect(
      mobileAutomationTabIsObserved(
        const <String, Object?>{
          'automationOwned': true,
          'automationTakenOver': true,
        },
        'tab',
        const {},
      ),
      isFalse,
    );
    expect(
      mobileAutomationTabIsObserved(const <String, Object?>{}, 'tab', const {}),
      isFalse,
    );
  });
}
