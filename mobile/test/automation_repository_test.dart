import 'package:alera_automations/alera_automations.dart';
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

  test('activating a draft resumes it; approve is never sent', () async {
    final client = FakeAutomationClient(
      automations: <Map<String, Object?>>[mobileAutomationJson(state: 'draft')],
    );
    addTearDown(client.dispose);
    final repository = MobileRuntimeAutomationRepository(client);
    final draft = (await repository.list()).single;
    await repository.activate(draft);
    expect(client.callsOf('automation.resume').single.payload, {
      'id': 'nightly',
    });
    expect(client.callsOf('automation.approve'), isEmpty);
  });

  test('unbind sends automation.unbind with the automation id', () async {
    final client = FakeAutomationClient();
    addTearDown(client.dispose);
    await MobileRuntimeAutomationRepository(client).unbind('nightly');
    expect(client.callsOf('automation.unbind').single.payload, {
      'id': 'nightly',
    });
  });

  test('reuse is detected from the runtime capabilities', () {
    final plain = FakeAutomationClient();
    final reusing = FakeAutomationClient(
      capabilities: <String>{'automationsV1', automationReuseCapability},
    );
    addTearDown(plain.dispose);
    addTearDown(reusing.dispose);
    expect(MobileRuntimeAutomationRepository(plain).supportsReuse, isFalse);
    expect(MobileRuntimeAutomationRepository(reusing).supportsReuse, isTrue);
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
