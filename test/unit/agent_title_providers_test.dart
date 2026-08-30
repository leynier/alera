import 'dart:async';

import 'package:alera/src/features/ai_assist/application/agent_title_providers.dart';
import 'package:alera/src/features/ai_assist/application/agent_title_service.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final initialFailure in [false, true]) {
    test(
      'availability recovers on the same client after ${initialFailure ? 'connection failure' : 'host upgrade'}',
      () async {
        final client = _Client()..fail = initialFailure;
        addTearDown(client.events.close);
        final container = ProviderContainer.test(
          overrides: [
            settingsControllerProvider.overrideWithValue(.defaults),
            agentTitleServiceProvider.overrideWithValue(
              AgentTitleService(client),
            ),
          ],
        );
        final subscription = container.listen(
          agentTitleAvailableProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);
        expect(
          await container.read(agentTitleAvailableProvider.future),
          isFalse,
        );

        client.fail = false;
        client.supported = true;
        client.events.add(
          const RuntimeHostEvent(aleraRuntimeHostConnectedEvent, {}),
        );
        await container.pump();
        expect(
          await container.read(agentTitleAvailableProvider.future),
          isTrue,
        );

        client.supported = false;
        client.events.add(
          const RuntimeHostEvent(aleraRuntimeHostConnectedEvent, {}),
        );
        await container.pump();
        expect(
          await container.read(agentTitleAvailableProvider.future),
          isFalse,
        );
        expect(client.requests, 3);
      },
    );
  }
}

class _Client extends Fake implements RuntimeHostClient {
  final events = StreamController<RuntimeHostEvent>.broadcast(sync: true);
  bool fail = false;
  bool supported = false;
  int requests = 0;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    expect(type, 'status.get');
    requests++;
    if (fail) throw StateError('Host unavailable');
    return {
      'runtimeCapabilities': [if (supported) agentTitleCapability],
    };
  }
}
