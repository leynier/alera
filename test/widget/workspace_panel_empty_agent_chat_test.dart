import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_launch_scope.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_tab_surface.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workbench_pane_focus_registry.dart';
import 'package:alera/src/features/workbench/presentation/workspace_panel_view.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';
import '../support/fake_agent_chat_settings_repository.dart';

final DateTime _now = DateTime.utc(2026, 10, 13);

Workspace _workspaceFixture(String id, String name) => Workspace(
  id: id,
  projectId: 'project-1',
  name: name,
  path: '/repo/alera',
  createdAt: _now,
  updatedAt: _now,
  kind: .main,
  status: .active,
);

final Workspace _workspace = _workspaceFixture('ws-1', 'Main');
final Workspace _otherWorkspace = _workspaceFixture('ws-2', 'Other');

/// The chat [agentChatSnapshotFixture] describes, so its tab can render.
WorkspaceTabRecord _chatTab(String tabId) => WorkspaceTabRecord(
  id: tabId,
  workspaceId: _workspace.id,
  kind: .agentChat,
  title: 'Agent Chat',
  createdAt: _now,
  updatedAt: _now,
  payload: <String, Object?>{
    AgentChatWire.chatIdKey: 'chat-1',
    AgentChatWire.providerKey: 'codex',
  },
);

typedef _Opened = ({String workspaceId, String tabId, bool activate});

final class _Workbench extends WorkbenchController {
  /// Tabs New Agent Chat asked to open. Every request opens only if its
  /// workspace is still current.
  final List<_Opened> opened = <_Opened>[];

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
      'project-1': <Workspace>[_workspace, _otherWorkspace],
    },
    activeProjectId: 'project-1',
    activeWorkspaceId: _workspace.id,
    bootstrapped: true,
  );

  /// Puts [tab] in its workspace, as the runtime's tab sync does.
  void showTab(WorkspaceTabRecord tab) => state = state.copyWith(
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      tab.workspaceId: <WorkspaceTabRecord>[tab],
    },
  );

  void selectWorkspaceId(String workspaceId) =>
      state = state.copyWith(activeWorkspaceId: workspaceId);

  void selectPanelKey(String key) => state = state.copyWith(
    viewPrefs: state.viewPrefs.copyWith(
      workspacePanels: <String, WorkspacePanel>{
        _workspace.id: state.workspacePanelFor(_workspace.id).select(key),
      },
    ),
  );

  @override
  Future<void> openPersistedWorkspaceTab({
    required String workspaceId,
    required String tabId,
    String? targetGroupId,
    int? sleepGeneration,
    bool activate = true,
    bool activateOnlyIfCurrent = false,
  }) async {
    expect(activateOnlyIfCurrent, isTrue);
    opened.add((workspaceId: workspaceId, tabId: tabId, activate: activate));
    if (activate && state.activeWorkspaceId == workspaceId) {
      showTab(_chatTab(tabId));
    }
  }
}

final class _Harness(
  final FakeAgentChatRepository repository,
  final _Workbench workbench,
) {
  final List<String> selected = <String>[];
  int terminals = 0;

  /// Holds the keyboard the way a focused terminal in the main area does.
  final FocusNode terminal = FocusNode(debugLabel: 'terminal');

  /// Another field the person can move to while a chat is created.
  final FocusNode field = FocusNode(debugLabel: 'field');

  List<AgentChatCreateInput> get creates => <AgentChatCreateInput>[
    for (final call in repository.calls)
      if (call.$1 == 'create') call.$2! as AgentChatCreateInput,
  ];
}

/// An empty side panel next to a focused "terminal". Once a chat tab is in
/// the workspace the panel shows it the way the side panel's single surface
/// does: in a focus scope and without autofocus.
Future<_Harness> _pumpEmptyPanel(
  WidgetTester tester, {
  bool supported = true,
  String tabId = 'tab-9',
}) async {
  final repository = FakeAgentChatRepository(isSupported: supported)
    ..providerCatalog = const <AgentChatProviderInstance>[
      AgentChatProviderInstance(id: 'codex', provider: 'codex', label: 'Codex'),
    ]
    ..snapshots.add(() => agentChatSnapshotFixture())
    ..createResult = AgentChatOpenResult(
      chatId: 'chat-1',
      tabId: tabId,
      snapshot: agentChatSnapshotFixture(),
    );
  final harness = _Harness(repository, _Workbench());
  addTearDown(harness.terminal.dispose);
  addTearDown(harness.field.dispose);
  var nextId = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatSettingsRepositoryProvider.overrideWithValue(
          FakeAgentChatSettingsRepository(preferencesEnabled: false),
        ),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
        agentChatClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 12, 10),
        ),
        workbenchControllerProvider.overrideWith(() => harness.workbench),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              Focus(
                focusNode: harness.terminal,
                child: const SizedBox(height: 8),
              ),
              TextField(focusNode: harness.field),
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final tab = ref.watch(
                      workbenchControllerProvider.select(
                        (state) => state.tabsFor(_workspace.id).firstOrNull,
                      ),
                    );
                    if (tab != null) {
                      return WorkbenchRegisteredFocusScope(
                        registryKey: WorkspacePanel.tabKey(tab.id),
                        registry: null,
                        debugLabel: 'WorkbenchSingleSurface ${tab.id}',
                        child: AgentChatTabSurface(
                          workspace: _workspace,
                          tab: tab,
                        ),
                      );
                    }
                    return AgentChatLaunchScope(
                      workspace: _workspace,
                      child: WorkspacePanelView(
                        workspaceId: _workspace.id,
                        panel: const WorkspacePanel(),
                        tabs: const [],
                        onSelect: harness.selected.add,
                        onClose: (_) {},
                        onNewTerminal: () => harness.terminals++,
                        onHide: () {},
                        content: const SizedBox.shrink(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  harness.terminal.requestFocus();
  await tester.pump();
  return harness;
}

final Finder _agentChatCard = find.text('Agent Chat');

final Finder _composerField = find.descendant(
  of: find.byKey(const ValueKey<String>('agent-chat-surface-chat-1')),
  matching: find.byType(EditableText),
);

bool _composerHasFocus(WidgetTester tester) =>
    tester.widget<EditableText>(_composerField).focusNode.hasFocus;

/// Taps the card and lets the launch reach the runtime's create.
Future<void> _tapAgentChat(WidgetTester tester) async {
  // The cards outgrow the default test surface; the panel scrolls.
  await tester.ensureVisible(_agentChatCard);
  await tester.tap(_agentChatCard);
  await tester.pump();
  await tester.pump();
}

/// Frames for the tab to mount, its chat to load and its focus to land.
Future<void> _settleOpenedChat(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump();
  }
}

void main() {
  testWidgets(
    'Agent Chat in an empty panel starts a chat in that panel without a '
    'dialog',
    (tester) async {
      final harness = await _pumpEmptyPanel(tester);
      expect(find.text('Panel is empty'), findsOneWidget);
      expect(_agentChatCard, findsOneWidget);
      expect(harness.creates, isEmpty);

      await _tapAgentChat(tester);
      await _settleOpenedChat(tester);

      expect(find.byType(Dialog), findsNothing);
      expect(harness.creates.single.workspaceId, _workspace.id);
      // No target group: the tab lands in the side panel's active group,
      // the same place the empty panel's Terminal card opens one.
      expect(harness.workbench.opened, <_Opened>[
        (workspaceId: _workspace.id, tabId: 'tab-9', activate: true),
      ]);
      expect(harness.selected, isEmpty);
      expect(harness.terminals, 0);
    },
  );

  testWidgets('an empty panel hides Agent Chat when the runtime lacks it', (
    tester,
  ) async {
    final harness = await _pumpEmptyPanel(tester, supported: false);
    expect(find.text('Panel is empty'), findsOneWidget);
    expect(find.text('Terminal'), findsOneWidget);
    expect(_agentChatCard, findsNothing);
    expect(harness.creates, isEmpty);
  });

  testWidgets(
    'the new chat takes the keyboard from the terminal in a panel that does '
    'not autofocus',
    (tester) async {
      final harness = await _pumpEmptyPanel(tester);
      expect(harness.terminal.hasFocus, isTrue);

      await _tapAgentChat(tester);
      await _settleOpenedChat(tester);

      expect(_composerField, findsOneWidget);
      expect(_composerHasFocus(tester), isTrue);
      expect(harness.terminal.hasFocus, isFalse);
    },
  );

  testWidgets(
    'a chat tab the runtime placed before the create answered still gets '
    'the keyboard',
    (tester) async {
      final harness = await _pumpEmptyPanel(tester);
      harness.repository.createGate = Completer<void>();
      await _tapAgentChat(tester);

      harness.workbench.showTab(_chatTab('tab-9'));
      await _settleOpenedChat(tester);
      expect(_composerHasFocus(tester), isFalse);

      harness.repository.createGate!.complete();
      await _settleOpenedChat(tester);

      expect(_composerHasFocus(tester), isTrue);
      expect(harness.terminal.hasFocus, isFalse);
    },
  );

  testWidgets(
    'a person who moved to another field while the chat started keeps it',
    (tester) async {
      final harness = await _pumpEmptyPanel(tester);
      harness.repository.createGate = Completer<void>();
      await _tapAgentChat(tester);

      harness.field.requestFocus();
      await tester.pump();
      harness.repository.createGate!.complete();
      await _settleOpenedChat(tester);

      expect(harness.workbench.opened.single.activate, isTrue);
      expect(_composerField, findsOneWidget);
      expect(_composerHasFocus(tester), isFalse);
      expect(harness.field.hasFocus, isTrue);
    },
  );

  testWidgets(
    'the card shows it is starting, ignores presses, and resets after a '
    'failure without creating a second chat',
    (tester) async {
      final harness = await _pumpEmptyPanel(tester);
      final gate = harness.repository.createGate = Completer<void>();
      harness.repository.createResult = null;
      final toasts = <String>[];
      final subscription = AleraToast.stream.listen(
        (toast) => toasts.add(toast.message),
      );
      addTearDown(subscription.cancel);

      await _tapAgentChat(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Starting the agent chat.'), findsOneWidget);

      await tester.tap(_agentChatCard);
      await tester.pump();
      expect(harness.creates, hasLength(1));

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Start an agent chat in a new tab.'), findsOneWidget);
      expect(toasts.single, startsWith('Could not start the chat'));
      expect(harness.workbench.opened, isEmpty);

      // Trying again reuses the request id, so the runtime cannot end up
      // with two chats for one press.
      harness.repository.createGate = null;
      await _tapAgentChat(tester);
      expect(harness.creates, hasLength(2));
      expect(harness.creates[1].requestId, harness.creates[0].requestId);
    },
  );

  testWidgets(
    'a chat whose workspace the person left while it started opens in the '
    'background',
    (tester) async {
      final harness = await _pumpEmptyPanel(tester);
      final gate = harness.repository.createGate = Completer<void>();
      await _tapAgentChat(tester);

      harness.workbench.selectWorkspaceId(_otherWorkspace.id);
      gate.complete();
      await _settleOpenedChat(tester);

      expect(harness.workbench.opened, <_Opened>[
        (workspaceId: _workspace.id, tabId: 'tab-9', activate: false),
      ]);
      expect(_composerField, findsNothing);
      expect(harness.terminal.hasFocus, isTrue);
    },
  );

  testWidgets(
    'a chat does not take the panel from a surface the person opened while '
    'it started',
    (tester) async {
      final harness = await _pumpEmptyPanel(tester);
      final gate = harness.repository.createGate = Completer<void>();
      await _tapAgentChat(tester);

      harness.workbench.selectPanelKey(WorkspaceTool.explorer.key);
      gate.complete();
      await _settleOpenedChat(tester);

      expect(harness.workbench.opened, <_Opened>[
        (workspaceId: _workspace.id, tabId: 'tab-9', activate: false),
      ]);
      expect(harness.terminal.hasFocus, isTrue);
    },
  );
}
