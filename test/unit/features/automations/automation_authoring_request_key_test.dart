import 'package:alera/src/features/automations/application/automation_authoring_controller.dart';
import 'package:alera/src/features/automations/domain/automation_draft.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/automation_test_harness.dart';

/// Answers the first create with a transport error, as an ambiguous response
/// whose outcome the client cannot know.
class _AmbiguousRuntime extends FakeAutomationRuntime {
  int failures = 1;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    if (type == 'automation.create' && failures > 0) {
      failures -= 1;
      requests.add((type: type, payload: payload));
      throw StateError('connection lost');
    }
    return super.runtimeRequest(type, payload, timeout);
  }
}

AutomationDraft _draft(String prompt) =>
    AutomationDraft(promptTemplate: prompt)
        .withTargetType(AutomationTargetType.freshTab)
        .withTargetField(.workspaceId, 'ws-1')
        .withTargetField(.agentProfileId, 'codex');

void main() {
  late _AmbiguousRuntime runtime;

  setUp(() => runtime = _AmbiguousRuntime());
  tearDown(() => runtime.dispose());

  List<Object?> keys() => runtime
      .requestsOf('automation.create')
      .map((request) => request.payload['requestKey'])
      .toList();

  test('retrying the same draft reuses its request key', () async {
    final container = automationContainer(runtime);
    addTearDown(container.dispose);
    final provider = automationAuthoringControllerProvider(1);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(provider.notifier)
      ..initialize(_draft('Review'));

    expect(await controller.submit(), isNull);
    expect(container.read(provider).error, contains('connection lost'));
    expect(await controller.submit(), isNotNull);
    expect(keys(), hasLength(2));
    expect(keys().first, keys().last);
  });

  test('a changed draft gets a new key so it is saved, not matched', () async {
    final container = automationContainer(runtime);
    addTearDown(container.dispose);
    final provider = automationAuthoringControllerProvider(2);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(provider.notifier)
      ..initialize(_draft('Review'));

    expect(await controller.submit(), isNull);
    controller.update(
      (draft) => draft.copyWith(promptTemplate: 'Review again'),
    );
    expect(await controller.submit(), isNotNull);
    expect(keys(), hasLength(2));
    expect(keys().first, isNot(keys().last));
  });
}
