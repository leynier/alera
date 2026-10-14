import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/design_system/layout/alera_key_value_row.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/domain/agent_provider_status.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/presentation/agent_provider_detail_screen.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/presentation/agent_providers_screen.dart';
import 'package:alera_mobile/src/features/projects/application/projects_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';
import 'support/fake_terminal_client.dart';

const Set<String> _settingsCapabilities = <String>{
  AgentChatWire.capability,
  AgentChatWire.providerSettingsCapability,
  AgentChatWire.preferencesCapability,
};

FakeAgentChatClient _client() {
  final client = FakeAgentChatClient(capabilities: _settingsCapabilities);
  client.handlers['agentChat.providers'] = (_) => <String, Object?>{
    'providers': <Object?>[
      agentChatProviderRow(
        'claudeAgent',
        label: 'Claude',
        auth: <String, Object?>{
          'status': 'signedIn',
          'checkedAt': '2026-10-12T10:00:00Z',
        },
      ),
      agentChatProviderRow('codex', label: 'Codex'),
    ],
  };
  client.handlers['agentChat.providerInstances.get'] = (_) => <String, Object?>{
    'revision': 7,
    'instances': <Object?>[
      <String, Object?>{
        'providerInstanceId': 'codex',
        'provider': 'codex',
        'enabled': true,
        'executable': '/opt/bin/codex',
        'args': <Object?>['--yolo'],
        'environment': <Object?>[
          <String, Object?>{'name': 'CODEX_HOME', 'value': '/data/codex'},
          <String, Object?>{
            'name': 'OPENAI_API_KEY',
            'sensitive': true,
            'value': 'must-never-show',
            'secretSaved': true,
          },
        ],
        'customModels': <Object?>[],
      },
    ],
  };
  client.handlers['agentChat.preferences.get'] = (_) => <String, Object?>{
    'revision': 3,
    'models': <String, Object?>{},
  };
  return client;
}

class _Projects extends ProjectsController {
  @override
  Future<ProjectManagementSnapshot> build(String hostId) async =>
      const ProjectManagementSnapshot(
        projects: <ProjectSummary>[
          ProjectSummary(id: 'project-1', name: 'Alera', repoPath: '/repo'),
        ],
        cloneJobs: [],
        supported: true,
      );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  FakeAgentChatClient client,
) async {
  final workspace = FakeTerminalClient();
  addTearDown(workspace.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mobileAgentChatClientProvider('host')
            .overrideWith((ref) async => client),
        workspaceClientProvider('host').overrideWith((ref) async => workspace),
        projectsControllerProvider('host').overrideWith(_Projects.new),
      ],
      child: const MaterialApp(home: AgentProvidersScreen(hostId: 'host')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('agentProviderStatusOf', () {
    test('Ready needs a verified sign-in', () {
      const verified = AgentChatProviderInstance(
        id: 'claudeAgent',
        provider: 'claudeAgent',
        label: 'Claude',
        auth: AgentChatProviderAuth(
          status: AgentChatProviderAuthStatus.signedIn,
          checkedAt: null,
        ),
      );
      expect(
        agentProviderStatusOf(verified),
        AgentProviderStatus.unknownSignIn,
      );
      final checked = AgentChatProviderInstance(
        id: 'claudeAgent',
        provider: 'claudeAgent',
        label: 'Claude',
        auth: AgentChatProviderAuth(
          status: AgentChatProviderAuthStatus.signedIn,
          checkedAt: DateTime.utc(2026, 10, 12),
        ),
      );
      expect(agentProviderStatusOf(checked), AgentProviderStatus.ready);
    });

    test('an executable alone never reads as signed in', () {
      const available = AgentChatProviderInstance(
        id: 'codex',
        provider: 'codex',
        label: 'Codex',
      );
      expect(agentProviderStatusOf(available).label, 'Unknown Sign-In');
    });

    test('off, missing and signed out read as such', () {
      expect(
        agentProviderStatusOf(
          const AgentChatProviderInstance(
            id: 'a',
            provider: 'a',
            label: 'A',
            enabled: false,
          ),
        ),
        AgentProviderStatus.off,
      );
      expect(
        agentProviderStatusOf(
          const AgentChatProviderInstance(
            id: 'a',
            provider: 'a',
            label: 'A',
            installed: false,
            available: false,
          ),
        ),
        AgentProviderStatus.notInstalled,
      );
      expect(
        agentProviderStatusOf(
          const AgentChatProviderInstance(
            id: 'a',
            provider: 'a',
            label: 'A',
            auth: AgentChatProviderAuth(
              status: AgentChatProviderAuthStatus.signedOut,
            ),
          ),
        ),
        AgentProviderStatus.signInNeeded,
      );
    });

    test('an unconfigured instance reads Setup Required, not Error', () {
      const unconfigured = AgentChatProviderInstance(
        id: 'acpRegistry',
        provider: 'acpRegistry',
        label: 'ACP Agent',
        available: false,
        setupRequired: true,
        unavailableReason: 'Launch failed: /private/path agent-cmd',
      );
      final status = agentProviderStatusOf(unconfigured);
      expect(status, AgentProviderStatus.setupRequired);
      expect(status.label, 'Setup Required');
      expect(status.healthy, isFalse);
      expect(
        agentProviderSetupRequiredDetail,
        isNot(contains('/private/path')),
      );
      // Off and Checking still win, matching desktop.
      expect(
        agentProviderStatusOf(
          const AgentChatProviderInstance(
            id: 'acpRegistry',
            provider: 'acpRegistry',
            label: 'ACP Agent',
            enabled: false,
            setupRequired: true,
          ),
        ),
        AgentProviderStatus.off,
      );
      expect(
        agentProviderStatusOf(unconfigured, checking: true),
        AgentProviderStatus.checking,
      );
      // A configured instance the runtime cannot start stays an error.
      expect(
        agentProviderStatusOf(
          const AgentChatProviderInstance(
            id: 'acpRegistry',
            provider: 'acpRegistry',
            label: 'ACP Agent',
            available: false,
          ),
        ),
        AgentProviderStatus.error,
      );
    });

    test('secret options use the host option prefix once', () {
      expect(agentProviderSecretOptionName('apiKey'), 'option:apiKey');
      expect(agentProviderSecretOptionName('option:apiKey'), 'option:apiKey');
    });
  });

  testWidgets('the list shows honest status and writes against a revision', (
    tester,
  ) async {
    final client = _client()
      ..handlers['agentChat.providerInstances.upsert'] = (_) =>
          <String, Object?>{'revision': 8, 'instances': <Object?>[]};
    await _pumpScreen(tester, client);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Unknown Sign-In'), findsOneWidget);
    expect(find.text('Default For New Chats'), findsOneWidget);

    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    final payload = client
        .payloadsOf('agentChat.providerInstances.upsert')
        .single;
    expect(payload['expectedRevision'], 7);
    expect(payload['instance'], <String, Object?>{
      'providerInstanceId': 'codex',
      'enabled': false,
    });
  });

  testWidgets('secrets are write-only and launch stays read-only', (
    tester,
  ) async {
    final client = _client()
      ..handlers['agentChat.secrets.set'] = (_) => <String, Object?>{
        'revision': 8,
        'instances': <Object?>[],
      };
    await _pumpScreen(tester, client);
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();

    // The detail list builds lazily; bring the launch section into view. The
    // provider list stays mounted under the pushed route, so scroll the
    // detail screen's own vertical list.
    final detailList = find
        .descendant(
          of: find.byType(AgentProviderDetailScreen),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('/opt/bin/codex'),
      200,
      scrollable: detailList,
    );
    expect(find.text('must-never-show'), findsNothing);
    expect(find.text('/opt/bin/codex'), findsOneWidget);
    expect(find.text('/data/codex'), findsOneWidget);
    expect(
      find.text('How this agent starts is edited on the desktop.'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('OPENAI_API_KEY'),
      200,
      scrollable: detailList,
    );
    expect(find.text('must-never-show'), findsNothing);
    expect(find.text('Saved'), findsOneWidget);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'sk-new');
    // Save enables once the typed value has been laid out.
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final payload = client.payloadsOf('agentChat.secrets.set').single;
    expect(payload['name'], 'OPENAI_API_KEY');
    expect(payload['value'], 'sk-new');
    expect(payload['expectedRevision'], 7);
    expect(find.text('sk-new'), findsNothing);
  });

  testWidgets('an ACP agent without an executable reads Not Set', (
    tester,
  ) async {
    final client = _client();
    client.handlers['agentChat.providers'] = (_) => <String, Object?>{
      'providers': <Object?>[
        <String, Object?>{
          ...agentChatProviderRow(
            'acpRegistry',
            label: 'Gemini Agent',
            available: false,
          ),
          'setupRequired': true,
        },
      ],
    };
    client.handlers['agentChat.providerInstances.get'] = (_) =>
        <String, Object?>{
          'revision': 7,
          'instances': <Object?>[
            <String, Object?>{
              'providerInstanceId': 'acpRegistry',
              'provider': 'acpRegistry',
              'enabled': true,
              'options': <String, Object?>{'agentId': 'gemini'},
              'customModels': <Object?>[],
            },
          ],
        };
    await _pumpScreen(tester, client);
    await tester.tap(find.text('Gemini Agent'));
    await tester.pumpAndSettle();

    final detailList = find
        .descendant(
          of: find.byType(AgentProviderDetailScreen),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Not Set'),
      200,
      scrollable: detailList,
    );
    // ACP registry agents have no default executable, so Default would lie.
    final executable = tester.widget<AleraKeyValueRow>(
      find.byWidgetPredicate(
        (widget) => widget is AleraKeyValueRow && widget.label == 'Executable',
      ),
    );
    expect(executable.value, 'Not Set');
  });

  testWidgets('a project default is one preferences write', (tester) async {
    final client = _client()
      ..handlers['agentChat.preferences.update'] = (_) => <String, Object?>{
        'revision': 4,
      };
    await _pumpScreen(tester, client);
    await tester.scrollUntilVisible(find.text('Alera'), 200);
    expect(find.text('Uses Default For New Chats'), findsOneWidget);
    await tester.tap(find.text('Alera'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('picker-claudeAgent-')));
    await tester.pumpAndSettle();

    final payload = client.payloadsOf('agentChat.preferences.update').single;
    expect(payload['expectedRevision'], 3);
    expect(payload['operations'], <Object?>[
      <String, Object?>{
        'type': 'setProjectDefault',
        'projectId': 'project-1',
        'selection': <String, Object?>{'providerInstanceId': 'claudeAgent'},
      },
    ]);
  });

  testWidgets('a lost race reloads instead of overwriting', (tester) async {
    var reads = 0;
    final client = _client();
    final read = client.handlers['agentChat.providerInstances.get']!;
    client
      ..handlers['agentChat.providerInstances.get'] = (payload) {
        reads += 1;
        return read(payload);
      }
      ..handlers['agentChat.providerInstances.upsert'] = (_) =>
          throw RuntimeRequestError('stale', code: 'revisionConflict');
    await _pumpScreen(tester, client);
    final before = reads;
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(find.textContaining('changed on another device'), findsOneWidget);
    expect(reads, greaterThan(before));
  });
}
