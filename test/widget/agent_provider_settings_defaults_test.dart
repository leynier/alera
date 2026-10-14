import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_provider_settings/application/agent_provider_settings_hosts.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_status.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_settings_pane.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_settings_repository.dart';

/// A runtime that advertises none of the additive chat capabilities.
final class const _NoRuntimeCapabilities() extends AgentChatLifecycleRepository;

void main() {
  final checkedAt = DateTime.now().subtract(const Duration(minutes: 2));

  // The host reports the effective label, so a customized instance's catalog
  // row already carries the custom name.
  List<AgentChatProviderInstance> catalog() => <AgentChatProviderInstance>[
    AgentChatProviderInstance(
      id: 'codex',
      provider: 'codex',
      label: 'QA CODEX',
      installed: true,
      checkedAt: checkedAt,
      auth: AgentChatProviderAuth(status: .signedIn, checkedAt: checkedAt),
      models: const <AgentChatModelOption>[
        AgentChatModelOption(id: 'gpt-6.1-sol', label: 'GPT-6.1-Sol'),
        AgentChatModelOption(id: 'gpt-6-astra', label: 'GPT-6-Astra'),
        AgentChatModelOption(id: 'gpt-5.5', label: 'GPT-5.5'),
      ],
    ),
    AgentChatProviderInstance(
      id: 'claudeAgent',
      provider: 'claudeAgent',
      label: 'Team Claude',
      installed: true,
      checkedAt: checkedAt,
    ),
    AgentChatProviderInstance(
      id: 'acpRegistry',
      provider: 'acpRegistry',
      label: 'ACP Agent',
      available: false,
      setupRequired: true,
      checkedAt: checkedAt,
      unavailableReason: 'Choose an ACP agent to launch.',
    ),
  ];

  AgentChatProviderInstanceEnvelope envelope(
    String id,
    String provider,
    String label, {
    String? defaultModel,
  }) => AgentChatProviderInstanceEnvelope(
    providerInstanceId: id,
    provider: provider,
    label: label,
    defaultModel: defaultModel,
  );

  Future<void> pumpPane(
    WidgetTester tester, {
    String? instanceDefault,
    String? personModel,
    String initialProviderInstanceId = 'codex',
  }) async {
    tester.view.physicalSize = const Size(1600, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeAgentChatSettingsRepository(
      revision: 5,
      catalog: catalog(),
      instances: <AgentChatProviderInstanceEnvelope>[
        envelope('codex', 'codex', 'QA CODEX', defaultModel: instanceDefault),
        envelope('claudeAgent', 'claudeAgent', 'Team Claude'),
      ],
      preferencesValue: AgentChatPreferences(
        revision: 2,
        defaultSelection: AgentChatSelection(
          providerInstanceId: 'codex',
          model: personModel,
        ),
      ),
    );
    addTearDown(fake.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentChatSettingsRepositoryProvider.overrideWithValue(fake),
          agentChatLifecycleRepositoryProvider.overrideWithValue(
            const _NoRuntimeCapabilities(),
          ),
          agentProviderHostOptionsProvider.overrideWithValue(
            const <AgentProviderHostOption>[
              AgentProviderHostOption(hostId: null, label: 'This Device'),
            ],
          ),
          agentProviderActiveWorkspaceHostProvider.overrideWithValue(null),
          agentProviderProjectsProvider.overrideWithValue(
            const <({String id, String name})>[],
          ),
        ],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 1500,
              height: 2500,
              child: AgentProviderSettingsPane(
                initialProviderInstanceId: initialProviderInstanceId,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder modelRow(String? id) =>
      find.byKey(ValueKey<String>('model-${id ?? '<default>'}'));

  Finder defaultBadgeIn(String? id) => find.descendant(
    of: modelRow(id),
    matching: find.widgetWithText(AleraBadge, 'Default'),
  );

  String defaultModelDropdownLabel(WidgetTester tester) {
    final dropdown = find.byWidgetPredicate(
      (widget) => widget is AleraDropdownField<String> && widget.value != null,
    );
    final field = tester.widget<AleraDropdownField<String>>(dropdown);
    return field.entries
        .singleWhere((entry) => entry.value == field.value)
        .label;
  }

  AleraIconButton iconButton(WidgetTester tester, String? id, String tooltip) =>
      tester.widget<AleraIconButton>(
        find.descendant(
          of: modelRow(id),
          matching: find.byWidgetPredicate(
            (widget) => widget is AleraIconButton && widget.tooltip == tooltip,
          ),
        ),
      );

  testWidgets('the label hint names the provider, not the custom label', (
    tester,
  ) async {
    await pumpPane(tester);

    expect(find.text('Leave empty to use Codex.'), findsOneWidget);
    expect(find.text('Leave empty to use QA CODEX.'), findsNothing);

    final label = find.descendant(
      of: find.byKey(const ValueKey<String>('label-codex')),
      matching: find.byType(TextField),
    );
    await tester.enterText(label, '');
    await tester.pumpAndSettle();
    // Clearing the label previews the name the host will use.
    final title = find.descendant(
      of: find.byKey(const ValueKey<String>('provider-detail--codex')),
      matching: find.text('Codex'),
    );
    expect(title, findsWidgets);
  });

  testWidgets('Claude Code is the fallback for a Claude instance', (
    tester,
  ) async {
    await pumpPane(tester, initialProviderInstanceId: 'claudeAgent');

    expect(find.text('Leave empty to use Claude Code.'), findsOneWidget);
  });

  testWidgets('without an instance default the provider default is marked', (
    tester,
  ) async {
    // The person's default names a model; that is not the instance default.
    await pumpPane(tester, personModel: 'gpt-6.1-sol');

    expect(defaultBadgeIn(null), findsOneWidget);
    expect(defaultBadgeIn('gpt-6.1-sol'), findsNothing);
    expect(defaultModelDropdownLabel(tester), 'GPT-6.1-Sol');
  });

  testWidgets('an unset model reads Provider Default with no instance '
      'default', (tester) async {
    await pumpPane(tester);

    expect(defaultModelDropdownLabel(tester), 'Provider Default');
  });

  testWidgets('an unset model names the configured instance default', (
    tester,
  ) async {
    await pumpPane(tester, instanceDefault: 'gpt-6-astra');

    expect(defaultBadgeIn('gpt-6-astra'), findsOneWidget);
    expect(defaultBadgeIn(null), findsNothing);
    expect(defaultModelDropdownLabel(tester), 'Instance Default (GPT-6-Astra)');
  });

  testWidgets('the last identified model cannot move below the provider '
      'default', (tester) async {
    await pumpPane(tester);

    expect(iconButton(tester, 'gpt-6.1-sol', 'Move Up').onPressed, isNull);
    expect(iconButton(tester, 'gpt-6.1-sol', 'Move Down').onPressed, isNotNull);
    expect(iconButton(tester, 'gpt-5.5', 'Move Up').onPressed, isNotNull);
    expect(iconButton(tester, 'gpt-5.5', 'Move Down').onPressed, isNull);
  });

  testWidgets('an unconfigured provider reads Setup Required in amber', (
    tester,
  ) async {
    await pumpPane(tester, initialProviderInstanceId: 'acpRegistry');

    expect(find.text('Error'), findsNothing);
    final badges = tester.widgetList<AleraBadge>(
      find.widgetWithText(AleraBadge, 'Setup Required'),
    );
    // The list row and the detail header.
    expect(badges, hasLength(2));
    expect(
      badges.map((badge) => badge.tone),
      everyElement(AleraBadgeTone.attention),
    );
    expect(find.text(agentProviderSetupRequiredDetail), findsOneWidget);
  });

  testWidgets('an ACP agent asks for an executable instead of promising '
      'PATH', (tester) async {
    await pumpPane(tester, initialProviderInstanceId: 'acpRegistry');

    expect(
      find.text(
        'Required. ACP agents have no default; enter a command on the host '
        'PATH or a full path.',
      ),
      findsOneWidget,
    );
    expect(find.text('Command or full path'), findsOneWidget);
    expect(find.text('Leave empty to find it on the host PATH.'), findsNothing);
    expect(find.text('Found on PATH'), findsNothing);
  });

  testWidgets('a built-in provider still finds its executable on PATH', (
    tester,
  ) async {
    await pumpPane(tester);

    expect(
      find.text('Leave empty to find it on the host PATH.'),
      findsOneWidget,
    );
    expect(find.text('Found on PATH'), findsOneWidget);
    expect(find.text('Command or full path'), findsNothing);
  });
}
