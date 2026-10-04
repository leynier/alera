import 'package:alera_mobile/src/features/automations/application/mobile_automation_authoring_controller.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_draft.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_automation_client.dart';

/// Fails the first create the way a dropped connection does: the client
/// cannot know whether the runtime stored it.
class _AmbiguousClient extends FakeAutomationClient {
  int failures = 1;

  @override
  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    if (type == 'automation.create' && failures > 0) {
      failures -= 1;
      calls.add((type: type, payload: payload));
      throw StateError('connection lost');
    }
    return super.request(type, payload, timeout);
  }
}

AutomationDraft _draft(String prompt) =>
    AutomationDraft(promptTemplate: prompt)
        .withTargetType(AutomationTargetType.freshTab)
        .withTargetField(.workspaceId, 'ws-1')
        .withTargetField(.agentProfileId, 'codex');

void main() {
  Future<List<Object?>> keysAfter(
    Future<void> Function(MobileAutomationAuthoringController controller) act,
  ) async {
    final client = _AmbiguousClient();
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        mobileAutomationClientProvider('host')
            .overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    final provider = mobileAutomationAuthoringControllerProvider('host', 1);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(provider.notifier)
      ..initialize(_draft('Review'));
    await act(controller);
    return client
        .callsOf('automation.create')
        .map((call) => call.payload['requestKey'])
        .toList();
  }

  test('retrying the same draft reuses its request key', () async {
    final keys = await keysAfter((controller) async {
      expect(await controller.submit(), isNull);
      expect(await controller.submit(), isNotNull);
    });
    expect(keys, hasLength(2));
    expect(keys.first, keys.last);
  });

  test('a changed draft gets a new request key', () async {
    final keys = await keysAfter((controller) async {
      expect(await controller.submit(), isNull);
      controller.update(
        (draft) => draft.copyWith(promptTemplate: 'Review again'),
      );
      expect(await controller.submit(), isNotNull);
    });
    expect(keys, hasLength(2));
    expect(keys.first, isNot(keys.last));
  });
}
