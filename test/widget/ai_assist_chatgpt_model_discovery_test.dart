import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_model_discovery_service.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_providers.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_registry.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/settings/presentation/panes/ai_assist_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/chatgpt_account_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('account change discards an older model catalog response', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final discovery = _DeferredDiscovery();
    final runtime = SocketTerminalHostClient(
      applicationSupportDirectory: () =>
          Future.error(StateError('Offline test runtime')),
    );
    addTearDown(runtime.dispose);
    var settings = const AiAssistSettings(agent: AiAssistAgent.chatgpt);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiAssistModelDiscoveryServiceProvider.overrideWithValue(discovery),
          runtimeHostClientProvider.overrideWithValue(runtime),
        ],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => AiAssistSettingsPane(
                  settings: settings,
                  onChanged: (update) =>
                      setState(() => settings = update(settings)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(discovery.requests, hasLength(1));
    tester
        .widget<ChatGptAccountSettings>(find.byType(ChatGptAccountSettings))
        .onAccountChanged();
    await tester.pump();
    expect(discovery.requests, hasLength(2));
    discovery.requests[1].complete(_catalog('current-account-model'));
    await tester.pump();
    discovery.requests[0].complete(_catalog('previous-account-model'));
    await tester.pump();
    expect(
      settings.discoveredModelsByAgent[AiAssistAgent.chatgpt]!.single.id,
      'current-account-model',
    );
    expect(
      settings.discoveredDefaultModelByAgent[AiAssistAgent.chatgpt],
      'current-account-model',
    );
    expect(tester.takeException(), isNull);
  });
}

AiAssistModelDiscoveryResult _catalog(String id) =>
    AiAssistModelDiscoveryResult(
      success: true,
      agent: AiAssistAgent.chatgpt,
      models: [AiAssistModel(id: id, label: id)],
      defaultModelId: id,
    );

class _DeferredDiscovery implements AiAssistModelDiscoveryService {
  final requests = <Completer<AiAssistModelDiscoveryResult>>[];

  @override
  Future<AiAssistModelDiscoveryResult> discover(AiAssistAgent agent) {
    final request = Completer<AiAssistModelDiscoveryResult>();
    requests.add(request);
    return request.future;
  }
}
