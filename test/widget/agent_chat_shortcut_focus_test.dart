import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';

import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/ai_assist/application/agent_title_providers.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_shortcuts_scope.dart';
import 'package:alera/src/features/projects/application/project_hosts_providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/infra/runtime_ssh_target_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/shell/presentation/alera_shell_page.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';
import '../support/inbox_test_client.dart';

// The real shell, so the chord travels the production focus path: composer
// field, chat surface, workbench pane scope, then KeyboardShortcutsScope.
final TargetPlatformVariant _macOS = TargetPlatformVariant.only(
  TargetPlatform.macOS,
);

final DateTime _now = DateTime.utc(2026, 10, 13);

final Project _project = Project(
  id: 'project-1',
  name: 'Alera',
  repoPath: '/repo/alera',
  createdAt: _now,
  updatedAt: _now,
);

final Workspace _mainWorkspace = Workspace(
  id: 'workspace-1',
  projectId: _project.id,
  name: 'Main',
  branch: 'main',
  path: _project.repoPath,
  createdAt: _now,
  updatedAt: _now,
  kind: .main,
  status: .active,
);

final Workspace _linkedWorkspace = Workspace(
  id: 'workspace-2',
  projectId: _project.id,
  name: 'Feature login',
  branch: 'feature/login',
  sourceBranch: 'main',
  path: '/repo/alera-feature-login',
  createdAt: _now,
  updatedAt: _now,
  kind: .linked,
  status: .active,
);

WorkspaceTabRecord _chatTab(Workspace workspace, String id, String chatId) =>
    WorkspaceTabRecord(
      id: id,
      workspaceId: workspace.id,
      kind: .agentChat,
      title: 'Agent Chat',
      createdAt: _now,
      updatedAt: _now,
      payload: <String, Object?>{
        AgentChatWire.chatIdKey: chatId,
        AgentChatWire.providerKey: 'codex',
      },
    );

/// Two workspaces, each showing one agent chat tab, with [_mainWorkspace]
/// active.
WorkbenchState _chatWorkbenchState() {
  final tabs = <String, List<WorkspaceTabRecord>>{
    _mainWorkspace.id: <WorkspaceTabRecord>[
      _chatTab(_mainWorkspace, 'tab-1', 'chat-1'),
    ],
    _linkedWorkspace.id: <WorkspaceTabRecord>[
      _chatTab(_linkedWorkspace, 'tab-2', 'chat-2'),
    ],
  };
  final layouts = <String, WorkbenchLayout>{
    for (final entry in tabs.entries)
      entry.key: WorkbenchLayout.single(
        workspaceId: entry.key,
        tabIds: <String>[for (final tab in entry.value) tab.id],
      ),
  };
  return WorkbenchState(
    projects: <Project>[_project],
    workspacesByProject: <String, List<Workspace>>{
      _project.id: <Workspace>[_mainWorkspace, _linkedWorkspace],
    },
    tabsByWorkspace: tabs,
    activeProjectId: _project.id,
    activeWorkspaceId: _mainWorkspace.id,
    activeTabIdByWorkspace: <String, String>{
      for (final entry in tabs.entries) entry.key: entry.value.single.id,
    },
    layoutByWorkspace: layouts,
    viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
      expandedWorkspaceIds: <String>{_mainWorkspace.id, _linkedWorkspace.id},
      workspacePanels: <String, WorkspacePanel>{
        for (final entry in tabs.entries)
          entry.key: const WorkspacePanel()
              .applyMainLayout(
                WorkbenchLayout.single(
                  workspaceId: entry.key,
                  tabIds: <String>[
                    WorkspacePanel.tabKey(entry.value.single.id),
                  ],
                ),
              )
              .select(WorkspacePanel.tabKey(entry.value.single.id)),
      },
    ),
    bootstrapped: true,
  );
}

class _ChatShellWorkbenchController(final WorkbenchState _seed)
    extends WorkbenchController {
  /// Tabs New Agent Chat asked to open, as (workspace, tab, only if current).
  final List<(String, String, bool)> opened = <(String, String, bool)>[];

  @override
  WorkbenchState build() => const WorkbenchState();

  @override
  Future<void> openPersistedWorkspaceTab({
    required String workspaceId,
    required String tabId,
    String? targetGroupId,
    int? sleepGeneration,
    bool activate = true,
    bool activateOnlyIfCurrent = false,
  }) async => opened.add((workspaceId, tabId, activateOnlyIfCurrent));

  @override
  Future<void> bootstrap() async => state = _seed;

  @override
  Future<List<String>> sleptTerminalIds(String workspaceId) async =>
      const <String>[];

  @override
  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) async {
    state = state.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: workspace.id,
    );
  }

  @override
  void selectWorkspacePanelKey(
    String workspaceId,
    String key, {
    String? groupId,
    bool recordSelection = true,
  }) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(
        workspacePanels: <String, WorkspacePanel>{
          ...state.viewPrefs.workspacePanels,
          workspaceId: state
              .workspacePanelFor(workspaceId)
              .select(key, groupId: groupId),
        },
      ),
    );
  }
}

/// No tab here is a terminal, so no session is ever asked for.
class _NoTerminalRuntime implements TerminalRuntime {
  final StreamController<TerminalRuntimeExitEvent> _exits =
      StreamController<TerminalRuntimeExitEvent>.broadcast();

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _exits.stream;

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) => throw StateError('Unexpected terminal session for ${tab.id}');

  @override
  TerminalSessionHandle? peekSession(String tabId) => null;

  @override
  void setActiveWorkspace(String? workspaceId) {}

  @override
  void closeTab(String tabId) {}

  @override
  void closeWorkspace(String workspaceId) {}

  @override
  void releaseTab(String tabId) {}

  @override
  void releaseWorkspace(String workspaceId) {}

  @override
  void dispose() => unawaited(_exits.close());
}

class _NoAgentProfiles extends AgentProfiles {
  @override
  Future<List<AgentProfile>> build() async => const <AgentProfile>[];
}

class _NoAgentStatus extends AgentStatusController {
  @override
  Map<String, AgentStatusEntry> build() => const <String, AgentStatusEntry>{};
}

class _DefaultSettings extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;
}

class _EmptyRuntimeHostClient implements RuntimeHostClient {
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async =>
      type == 'sshTarget.list' ? const <Object?>[] : const <String, Object?>{};
}

Future<_ChatShellWorkbenchController> _pumpChatShell(
  WidgetTester tester,
  FakeAgentChatRepository repository,
) async {
  final controller = _ChatShellWorkbenchController(_chatWorkbenchState());
  final db = AleraDatabase(executor: NativeDatabase.memory());
  addTearDown(db.close);
  var nextId = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
        ...inboxClientOverrides(InboxTestClient()..supported = false),
        aleraDatabaseProvider.overrideWith((ref) async => db),
        workbenchControllerProvider.overrideWith(() => controller),
        agentProfilesProvider.overrideWith(_NoAgentProfiles.new),
        agentStatusControllerProvider.overrideWith(_NoAgentStatus.new),
        agentQuotaStateProvider.overrideWith(
          (ref) async => AgentQuotaState.empty('local'),
        ),
        sshTargetRepositoryProvider.overrideWithValue(
          RuntimeSshTargetRepository(_EmptyRuntimeHostClient()),
        ),
        terminalRuntimeProvider.overrideWith((ref) => _NoTerminalRuntime()),
        terminalHostWarmupCoordinatorProvider.overrideWith((ref) {}),
        settingsControllerProvider.overrideWith(_DefaultSettings.new),
        agentTitleAvailableProvider.overrideWith((ref) async => false),
        projectHostsSupportedProvider.overrideWith((ref) async => false),
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
        agentChatClockProvider.overrideWithValue(() => _now),
      ],
      child: MaterialApp(home: AleraShellPage()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
  return controller;
}

/// A runtime whose chats already sent a message, so New Agent Chat creates a
/// chat instead of reusing one. [sent] false keeps them never-sent.
FakeAgentChatRepository _supportedRepository({bool sent = true}) =>
    FakeAgentChatRepository(isSupported: true)
      ..providerCatalog = const <AgentChatProviderInstance>[
        AgentChatProviderInstance(
          id: 'codex',
          provider: 'codex',
          label: 'Codex',
        ),
      ]
      ..createResult = AgentChatOpenResult(
        chatId: 'chat-9',
        tabId: 'tab-9',
        snapshot: agentChatSnapshotFixture(),
      )
      ..snapshots.add(
        () => agentChatSnapshotFixture(
          items: sent
              ? <Map<String, Object?>>[
                  agentChatItemFixture('u1', 'user_message', text: 'Hello'),
                ]
              : const <Map<String, Object?>>[],
        ),
      );

List<AgentChatCreateInput> _creates(FakeAgentChatRepository repository) =>
    <AgentChatCreateInput>[
      for (final call in repository.calls)
        if (call.$1 == 'create') call.$2! as AgentChatCreateInput,
    ];

Future<void> _pressChord(
  WidgetTester tester,
  List<LogicalKeyboardKey> modifiers,
  LogicalKeyboardKey key,
) async {
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyEvent(key);
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pumpAndSettle();
}

/// Cmd+Shift+T, the macOS default of New Agent Chat.
Future<void> _pressNewAgentChat(WidgetTester tester) =>
    _pressChord(tester, <LogicalKeyboardKey>[.metaLeft, .shiftLeft], .keyT);

Finder get _composerField => find.descendant(
  of: find.byKey(const ValueKey<String>('agent-chat-surface-chat-1')),
  matching: find.byType(EditableText),
);

/// Whether the primary focus is the global shortcut layer or sits under it,
/// the only places a chord pressed outside a terminal is dispatched from.
bool _focusReachesShortcutScope() {
  final focus = FocusManager.instance.primaryFocus;
  return focus != null &&
      <FocusNode>[
        focus,
        ...focus.ancestors,
      ].any((node) => node.debugLabel == 'KeyboardShortcutsScope');
}

void main() {
  testWidgets(
    'Cmd+Shift+T in a focused chat composer starts a chat without a dialog',
    (tester) async {
      final repository = _supportedRepository();
      final controller = await _pumpChatShell(tester, repository);

      await tester.tap(_composerField);
      await tester.pumpAndSettle();
      final field = tester.widget<EditableText>(_composerField);
      expect(field.focusNode.hasPrimaryFocus, isTrue);
      expect(find.byType(KeyboardShortcutsScope), findsOneWidget);
      expect(_focusReachesShortcutScope(), isTrue);

      // Ctrl is not the macOS Mod key, so the same chord on Ctrl must not
      // match: this pins the test to the Mac binding rather than Linux's.
      await _pressChord(tester, <LogicalKeyboardKey>[
        .controlLeft,
        .shiftLeft,
      ], .keyT);
      expect(_creates(repository), isEmpty);

      await _pressNewAgentChat(tester);

      expect(find.byType(Dialog), findsNothing);
      final create = _creates(repository).single;
      expect(create.workspaceId, _mainWorkspace.id);
      // The new chat inherits the agent of the chat it was started from.
      expect(create.providerInstanceId, 'codex');
      expect(create.model, 'gpt-5');
      expect(controller.opened, <(String, String, bool)>[
        (_mainWorkspace.id, 'tab-9', true),
      ]);
      // The chord is a shortcut, not typing: the draft stays empty.
      expect(field.controller.text, isEmpty);
    },
    variant: _macOS,
  );

  testWidgets(
    'Cmd+Shift+T after picking a workspace in the sidebar starts a chat '
    'there',
    (tester) async {
      final repository = _supportedRepository();
      final controller = await _pumpChatShell(tester, repository);
      await tester.tap(_composerField);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Feature login'));
      await tester.pumpAndSettle();
      expect(controller.state.activeWorkspaceId, _linkedWorkspace.id);
      expect(
        find.byKey(const ValueKey<String>('agent-chat-surface-chat-2')),
        findsOneWidget,
      );
      // The sidebar row hands the keyboard back to the shortcut layer rather
      // than parking it on the route above, where no chord is dispatched.
      expect(_focusReachesShortcutScope(), isTrue);

      await _pressNewAgentChat(tester);

      expect(_creates(repository).single.workspaceId, _linkedWorkspace.id);
      expect(controller.opened.single.$1, _linkedWorkspace.id);
    },
    variant: _macOS,
  );

  testWidgets(
    'Cmd+Shift+T focuses a never-sent chat with an empty draft instead',
    (tester) async {
      final repository = _supportedRepository(sent: false);
      final controller = await _pumpChatShell(tester, repository);
      await tester.tap(_composerField);
      await tester.pumpAndSettle();

      await _pressNewAgentChat(tester);

      expect(_creates(repository), isEmpty);
      expect(controller.opened, isEmpty);
      expect(controller.state.activeWorkspaceId, _mainWorkspace.id);
      final field = tester.widget<EditableText>(_composerField);
      expect(field.focusNode.hasPrimaryFocus, isTrue);
    },
    variant: _macOS,
  );

  testWidgets('a never-sent chat with unsent text is not reused', (
    tester,
  ) async {
    final repository = _supportedRepository(sent: false);
    await _pumpChatShell(tester, repository);
    await tester.tap(_composerField);
    await tester.pumpAndSettle();
    await tester.enterText(_composerField, 'Draft in progress');
    await tester.pump();

    await _pressNewAgentChat(tester);

    expect(_creates(repository), hasLength(1));
    expect(
      tester.widget<EditableText>(_composerField).controller.text,
      'Draft in progress',
    );
  }, variant: _macOS);

  testWidgets('Cmd+Shift+M opens the agent and model picker', (tester) async {
    await _pumpChatShell(tester, _supportedRepository());
    await tester.tap(_composerField);
    await tester.pumpAndSettle();

    await _pressChord(tester, <LogicalKeyboardKey>[
      .metaLeft,
      .shiftLeft,
    ], .keyM);

    expect(find.text(agentChatPickerSearchHint), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(agentChatPickerSearchHint), findsNothing);
  }, variant: _macOS);
}
