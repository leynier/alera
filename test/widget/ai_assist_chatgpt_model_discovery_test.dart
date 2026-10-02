import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_model_discovery_service.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_providers.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_registry.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/settings/presentation/panes/ai_assist_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/ai_assist_setting_rows.dart';
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

  testWidgets('retries discovery when the account becomes ready', (
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

    discovery.requests[0].complete(_failedCatalog());
    await tester.pump();
    tester
        .widget<ChatGptAccountSettings>(find.byType(ChatGptAccountSettings))
        .onAccountReady!
        .call();
    await tester.pump();

    expect(discovery.requests, hasLength(2));
    discovery.requests[1].complete(_catalog('current-account-model'));
    await tester.pump();
    expect(
      settings.discoveredModelsByAgent[AiAssistAgent.chatgpt]!.single.id,
      'current-account-model',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps a saved ChatGPT model visible when refresh fails', (
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
    var settings = const AiAssistSettings(
      agent: AiAssistAgent.chatgpt,
      selectedModelByAgent: <AiAssistAgent, String>{
        AiAssistAgent.chatgpt: 'gpt-6-sol',
      },
      discoveredModelsByAgent: <AiAssistAgent, List<AiAssistDiscoveredModel>>{
        AiAssistAgent.chatgpt: <AiAssistDiscoveredModel>[
          AiAssistDiscoveredModel(id: 'gpt-5.5', label: 'GPT-5.5'),
        ],
      },
    );
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
    discovery.requests.single.complete(_failedCatalog());
    await tester.pump();

    expect(find.textContaining('Unavailable ('), findsOneWidget);
    final modelRow = find.ancestor(
      of: find.byKey(
        const ValueKey<String>('ai-assist-model-chatgpt-gpt-6-sol'),
      ),
      matching: find.byType(AleraSettingRow),
    );
    expect(
      find.descendant(
        of: modelRow,
        matching: find.text('ChatGPT account is not ready.'),
      ),
      findsOneWidget,
    );
    expect(
      settings.discoveredModelsFor(AiAssistAgent.chatgpt).single.id,
      'gpt-5.5',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows speed and inherited reasoning for prompt ChatGPT', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final discovery = _DeferredDiscovery();
    final runtime = SocketTerminalHostClient(
      applicationSupportDirectory: () =>
          Future.error(StateError('Offline test runtime')),
    );
    addTearDown(runtime.dispose);
    var settings = const AiAssistSettings(
      agent: AiAssistAgent.codex,
      promptSettingsByOperation: <AiAssistOperation, AiAssistPromptSettings>{
        AiAssistOperation.commitMessage: AiAssistPromptSettings(
          agent: AiAssistAgent.chatgpt,
        ),
      },
      discoveredModelsByAgent: <AiAssistAgent, List<AiAssistDiscoveredModel>>{
        AiAssistAgent.chatgpt: <AiAssistDiscoveredModel>[
          AiAssistDiscoveredModel(
            id: 'gpt-6-sol',
            label: 'GPT-6 Sol',
            thinkingLevels: <AiAssistDiscoveredThinkingLevel>[
              AiAssistDiscoveredThinkingLevel(id: 'low', label: 'Low'),
              AiAssistDiscoveredThinkingLevel(id: 'high', label: 'High'),
            ],
            defaultThinkingLevel: 'low',
          ),
        ],
      },
      selectedModelByAgent: <AiAssistAgent, String>{
        AiAssistAgent.chatgpt: 'gpt-6-sol',
      },
      selectedThinkingByModel: <String, String>{'gpt-6-sol': 'high'},
      selectedThinkingByOperation: <AiAssistOperation, Map<String, String>>{
        AiAssistOperation.commitMessage: <String, String>{'gpt-6-sol': 'low'},
      },
    );
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

    expect(find.text('ChatGPT Speed'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    final reasoning = tester.widget<AiAssistThinkingRow>(
      find.ancestor(
        of: find.byKey(
          const ValueKey<String>('ai-assist-commitMessage-reasoning-low'),
        ),
        matching: find.byType(AiAssistThinkingRow),
      ),
    );
    expect(reasoning.allowInherited, isTrue);
    expect(reasoning.allowProviderDefault, isFalse);
    expect(reasoning.value, 'low');
    expect(reasoning.inheritedLabel, 'Inherit Global (High)');
    reasoning.onChanged(null);
    await tester.pump();
    expect(
      settings.thinkingForOperation(
        AiAssistOperation.commitMessage,
        'gpt-6-sol',
      ),
      'high',
    );
    final speed = tester.widget<ChatGptModelSpeedRow>(
      find.byType(ChatGptModelSpeedRow),
    );
    speed.onChanged(aiAssistChatGptFastServiceTier);
    await tester.pump();
    expect(
      settings.effectiveChatGptServiceTier,
      aiAssistChatGptFastServiceTier,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows stale global reasoning and keeps Fast visible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final discovery = _DeferredDiscovery();
    final runtime = SocketTerminalHostClient(
      applicationSupportDirectory: () =>
          Future.error(StateError('Offline test runtime')),
    );
    addTearDown(runtime.dispose);
    var settings = const AiAssistSettings(
      agent: AiAssistAgent.codex,
      chatGptServiceTier: aiAssistChatGptFastServiceTier,
      promptSettingsByOperation: <AiAssistOperation, AiAssistPromptSettings>{
        AiAssistOperation.commitMessage: AiAssistPromptSettings(
          agent: AiAssistAgent.chatgpt,
        ),
      },
      discoveredModelsByAgent: <AiAssistAgent, List<AiAssistDiscoveredModel>>{
        AiAssistAgent.chatgpt: <AiAssistDiscoveredModel>[
          AiAssistDiscoveredModel(
            id: 'gpt-6-sol',
            label: 'GPT-6 Sol',
            thinkingLevels: <AiAssistDiscoveredThinkingLevel>[
              AiAssistDiscoveredThinkingLevel(id: 'low', label: 'Low'),
              AiAssistDiscoveredThinkingLevel(id: 'high', label: 'High'),
            ],
          ),
        ],
      },
      selectedModelByAgent: <AiAssistAgent, String>{
        AiAssistAgent.chatgpt: 'gpt-6-sol',
      },
      selectedThinkingByModel: <String, String>{'gpt-6-sol': 'ultra'},
    );
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

    expect(find.text('Unavailable (Global: ultra)'), findsOneWidget);
    expect(
      find.textContaining(
        'Choose Provider Default in the global AI Assist settings',
      ),
      findsOneWidget,
    );
    final reasoning = tester.widget<AiAssistThinkingRow>(
      find.ancestor(
        of: find.byKey(
          const ValueKey<String>('ai-assist-commitMessage-reasoning-inherit'),
        ),
        matching: find.byType(AiAssistThinkingRow),
      ),
    );
    expect(reasoning.inheritedUnavailableValue, 'ultra');
    reasoning.onChanged('high');
    await tester.pump();
    expect(
      settings.selectedThinkingByOperation[AiAssistOperation
          .commitMessage]?['gpt-6-sol'],
      'high',
    );

    final speed = tester.widget<ChatGptModelSpeedRow>(
      find.byType(ChatGptModelSpeedRow),
    );
    speed.onChanged(aiAssistChatGptDefaultServiceTier);
    await tester.pump();
    expect(
      settings.effectiveChatGptServiceTier,
      aiAssistChatGptDefaultServiceTier,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps Normal selectable when Fast is unavailable', (
    tester,
  ) async {
    String selected = aiAssistChatGptFastServiceTier;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: ChatGptModelSpeedRow(
            value: selected,
            enabled: false,
            availabilityMessage: 'Update Alera to use ChatGPT speed controls.',
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    final dropdown = tester.widget<AleraDropdownField<String>>(
      find.byKey(const ValueKey<String>('ai-assist-chatgpt-speed-fast')),
    );
    expect(dropdown.enabled, isTrue);
    expect(
      dropdown.entries
          .singleWhere((entry) => entry.value == aiAssistChatGptFastServiceTier)
          .enabled,
      isFalse,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('ai-assist-chatgpt-speed-fast')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Normal'));
    await tester.pump();
    expect(selected, aiAssistChatGptDefaultServiceTier);
  });
}

AiAssistModelDiscoveryResult _catalog(String id) =>
    AiAssistModelDiscoveryResult(
      success: true,
      agent: AiAssistAgent.chatgpt,
      models: [AiAssistModel(id: id, label: id)],
      defaultModelId: id,
    );

AiAssistModelDiscoveryResult _failedCatalog() =>
    const AiAssistModelDiscoveryResult(
      success: false,
      agent: AiAssistAgent.chatgpt,
      models: <AiAssistModel>[],
      defaultModelId: null,
      error: 'ChatGPT account is not ready.',
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
