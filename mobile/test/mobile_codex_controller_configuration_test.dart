import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void mobileCodexConfigurationTest() {
  test('mobile controller restores supported effort from the tab', () async {
    final client = FakeMobileCodexClient(
      configuration: <String, Object?>{
        'selectedModel': 'gpt-current',
        'reasoningEffort': 'xhigh',
        'speedMode': 'normal',
        'permissionMode': 'on-request',
        'planMode': false,
        'collaborationMode': null,
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-config',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider('host-config', 'tab-config');
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final state = await container.read(provider.future);

    expect(state.reasoningEffort, 'xhigh');
    final openCall = client.calls.singleWhere(
      (call) => call.type == 'codex.thread.open',
    );
    expect(openCall.payload['supportsMissingRolloutRecovery'], isTrue);
  });
}

void main() => mobileCodexConfigurationTest();
