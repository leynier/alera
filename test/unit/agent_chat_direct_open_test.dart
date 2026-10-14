import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_direct_open.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';
import '../support/fake_agent_chat_settings_repository.dart';

final DateTime _now = DateTime.utc(2026, 10, 13);

final Workspace _workspace = Workspace(
  id: 'ws-1',
  projectId: 'project-1',
  name: 'Main',
  path: '/repo/alera',
  createdAt: _now,
  updatedAt: _now,
  kind: .main,
  status: .active,
);

final class _Workbench extends WorkbenchController {
  final List<(String, String, bool)> opened = <(String, String, bool)>[];

  @override
  WorkbenchState build() => WorkbenchState(
    projects: <Project>[
      Project(
        id: 'project-1',
        name: 'Alera',
        repoPath: '/repo/alera',
        createdAt: _now,
        updatedAt: _now,
      ),
    ],
    workspacesByProject: <String, List<Workspace>>{
      'project-1': <Workspace>[_workspace],
    },
    activeProjectId: 'project-1',
    activeWorkspaceId: _workspace.id,
    bootstrapped: true,
  );

  @override
  Future<void> openPersistedWorkspaceTab({
    required String workspaceId,
    required String tabId,
    String? targetGroupId,
    int? sleepGeneration,
    bool activate = true,
    bool activateOnlyIfCurrent = false,
  }) async => opened.add((workspaceId, tabId, activateOnlyIfCurrent));
}

const AgentChatProviderInstance _codex = AgentChatProviderInstance(
  id: 'codex',
  provider: 'codex',
  label: 'Codex',
);

const AgentChatProviderInstance _cursor = AgentChatProviderInstance(
  id: 'cursor',
  provider: 'cursor',
  label: 'Cursor',
  available: false,
  unavailableReason: 'Sign in to Cursor first.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAgentChatRepository repository;
  late FakeAgentChatSettingsRepository settings;
  late _Workbench workbench;
  late ProviderContainer container;
  late int nextId;

  setUp(() {
    repository = FakeAgentChatRepository()
      ..providerCatalog = const <AgentChatProviderInstance>[_codex]
      ..createResult = AgentChatOpenResult(
        chatId: 'chat-9',
        tabId: 'tab-9',
        snapshot: agentChatSnapshotFixture(),
      );
    settings = FakeAgentChatSettingsRepository(preferencesEnabled: false);
    workbench = _Workbench();
    nextId = 0;
    container = ProviderContainer(
      overrides: [
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatSettingsRepositoryProvider.overrideWithValue(settings),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
        workbenchControllerProvider.overrideWith(() => workbench),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<AgentChatDirectOpenOutcome> open() => container
      .read(agentChatDirectOpenerProvider)
      .open(
        read: container.read,
        exists: container.exists,
        workspace: _workspace,
        targetGroupId: 'group-1',
      );

  List<AgentChatCreateInput> creates() => <AgentChatCreateInput>[
    for (final call in repository.calls)
      if (call.$1 == 'create') call.$2! as AgentChatCreateInput,
  ];

  test('opens the created chat without switching workspaces', () async {
    expect(await open(), AgentChatDirectOpenOutcome.created);
    expect(creates().single.providerInstanceId, 'codex');
    // The provider default is left to the runtime rather than guessed.
    expect(creates().single.toJson().containsKey('model'), isFalse);
    expect(workbench.opened, <(String, String, bool)>[
      (_workspace.id, 'tab-9', true),
    ]);
  });

  test('the project default outranks the remembered selection', () async {
    settings
      ..preferencesEnabled = true
      ..preferencesValue = const AgentChatPreferences(
        rememberedSelection: AgentChatSelection(providerInstanceId: 'codex'),
        projectDefaults: <String, AgentChatSelection>{
          'project-1': AgentChatSelection(
            providerInstanceId: 'claudeAgent',
            model: 'opus',
          ),
        },
      );
    repository.providerCatalog = const <AgentChatProviderInstance>[
      _codex,
      AgentChatProviderInstance(
        id: 'claudeAgent',
        provider: 'claudeAgent',
        label: 'Claude',
      ),
    ];
    await open();
    expect(creates().single.providerInstanceId, 'claudeAgent');
    expect(creates().single.model, 'opus');
  });

  test(
    'a runtime without preferences uses this session\'s last chat',
    () async {
      repository.providerCatalog = const <AgentChatProviderInstance>[
        _codex,
        AgentChatProviderInstance(id: 'pi', provider: 'pi', label: 'Pi'),
      ];
      container
          .read(agentChatLaunchPreferenceProvider.notifier)
          .remember(const AgentChatSelection(providerInstanceId: 'pi'));
      await open();
      expect(creates().single.providerInstanceId, 'pi');
    },
  );

  test('an agent that cannot start yet still gets its chat', () async {
    repository.providerCatalog = const <AgentChatProviderInstance>[_cursor];
    expect(await open(), AgentChatDirectOpenOutcome.created);
    expect(creates().single.providerInstanceId, 'cursor');
  });

  test('without any enabled agent nothing is created', () async {
    repository.providerCatalog = const <AgentChatProviderInstance>[
      AgentChatProviderInstance(
        id: 'codex',
        provider: 'codex',
        label: 'Codex',
        enabled: false,
      ),
    ];
    expect(await open(), AgentChatDirectOpenOutcome.failed);
    expect(creates(), isEmpty);
    expect(workbench.opened, isEmpty);
  });

  test('a failed create retries with the same request id', () async {
    final result = repository.createResult;
    repository.createResult = null;
    expect(await open(), AgentChatDirectOpenOutcome.failed);
    repository.createResult = result;
    expect(await open(), AgentChatDirectOpenOutcome.created);
    expect(await open(), AgentChatDirectOpenOutcome.created);
    final ids = <String>[for (final input in creates()) input.requestId];
    expect(ids[0], ids[1]);
    expect(ids[2], isNot(ids[1]));
  });

  test('a second press while one is opening is skipped', () async {
    final first = open();
    expect(await open(), AgentChatDirectOpenOutcome.skipped);
    expect(await first, AgentChatDirectOpenOutcome.created);
    expect(creates(), hasLength(1));
  });
}
