part of 'workspace_workbench_view_test.dart';

void _registerWorkspaceWorkbenchViewTabTests() {
  for (final kind in [WorkspaceTabKind.terminal, WorkspaceTabKind.codex]) {
    for (final mode in ['unsupported', 'new', 'generated', 'generating']) {
      testWidgets('title action respects $kind capability and $mode state', (
        tester,
      ) async {
        final tab = _tab('title-tab', title: 'Agent Task', kind: kind).copyWith(
          payload: <String, Object?>{
            if (mode == 'generated') 'agentTitleSource': 'generated',
            if (mode == 'generating') 'agentTitleStatus': 'generating',
          },
        );
        await _pumpWorkbenchView(
          tester,
          tabs: [
            tab,
            _tab('shell', title: 'Shell'),
          ],
          terminalRuntime: terminalRuntime,
          layout: .single(
            workspaceId: _workspaceId,
            groupId: 'group-a',
            tabIds: [tab.id, 'shell'],
          ),
          createdTabs: createdTabs,
          selectedTabs: selectedTabs,
          closedTabs: closedTabs,
          closedTabGroups: closedTabGroups,
          renamedTabs: renamedTabs,
          movedTabs: movedTabs,
          splitGroups: splitGroups,
          mergedGroups: mergedGroups,
          updatedRatios: updatedRatios,
          agentTitlesAvailable: mode != 'unsupported',
        );
        await tester.pumpAndSettle();
        await _openTabContextMenu(tester, 'Agent Task');
        final label = mode == 'generating'
            ? 'Generating title...'
            : mode == 'generated'
            ? 'Regenerate Title'
            : 'Generate Title';
        expect(
          find.text(label),
          mode == 'unsupported' ? findsNothing : findsOneWidget,
        );
        if (kind == WorkspaceTabKind.terminal && mode != 'unsupported') {
          expect(
            tester.getTopLeft(find.text('Change Title')).dy,
            lessThan(tester.getTopLeft(find.text(label)).dy),
          );
        }
        if (mode != 'unsupported') {
          final entry = tester.widget<AleraDropdownEntry<Object?>>(
            find.ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (widget) => widget is AleraDropdownEntry,
              ),
            ),
          );
          expect(entry.leading, isA<Icon>());
          expect((entry.leading! as Icon).size, 16);
          expect((entry.leading! as Icon).icon, AleraIcons.ai);
        }
        if (mode == 'generating') {
          expect(find.byTooltip('Generating title...'), findsOneWidget);
          final entry = tester.widget<AleraDropdownEntry<Object?>>(
            find.ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (widget) => widget is AleraDropdownEntry,
              ),
            ),
          );
          expect(entry.enabled, isFalse);
        }
      });
    }
  }

  testWidgets('Codex tab context menu does not offer generic rename', (
    tester,
  ) async {
    final terminal = _tab('terminal-1', title: 'Terminal');
    final codex = _tab('codex-1', title: 'Generated title', kind: .codex);
    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[codex, terminal],
      terminalRuntime: terminalRuntime,
      layout: .single(
        workspaceId: _workspaceId,
        groupId: 'group-a',
        tabIds: <String>[codex.id, terminal.id],
      ),
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
    );

    await _openTabContextMenu(tester, 'Generated title');
    expect(find.text('Change Title'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('tab context menu closes sibling tabs', (tester) async {
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Terminal 1'),
      _tab('tab-2', title: 'Terminal 2'),
      _tab('tab-3', title: 'Terminal 3'),
    ];

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: .single(
        workspaceId: _workspaceId,
        groupId: 'group-a',
        tabIds: tabs.map((tab) => tab.id).toList(),
      ),
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
    );

    await _openTabContextMenu(tester, 'Terminal 2');
    await tester.tap(find.text('Close Others'));
    await tester.pumpAndSettle();

    expect(closedTabGroups, <List<String>>[
      <String>['tab-1', 'tab-3'],
    ]);

    await _openTabContextMenu(tester, 'Terminal 2');
    await tester.tap(find.text('Close Tabs to the Right'));
    await tester.pumpAndSettle();

    expect(closedTabGroups, <List<String>>[
      <String>['tab-1', 'tab-3'],
      <String>['tab-3'],
    ]);
  });

  testWidgets('tab context menu renames and splits the active group', (
    tester,
  ) async {
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Terminal 1'),
      _tab('tab-2', title: 'Terminal 2'),
    ];

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: .single(
        workspaceId: _workspaceId,
        groupId: 'group-a',
        tabIds: tabs.map((tab) => tab.id).toList(),
      ),
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
    );

    await _openTabContextMenu(tester, 'Terminal 2');
    await tester.tap(find.text('Change Title'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Renamed terminal');
    await tester.tap(find.text('Change Title').last);
    await tester.pumpAndSettle();

    expect(renamedTabs, <String>['Renamed terminal']);

    await _openTabContextMenu(tester, 'Terminal 2');
    await tester.tap(find.text('Split Right'));
    await tester.pumpAndSettle();

    expect(splitGroups, contains(const _SplitGroupAction('group-a', .right)));
  });

  testWidgets('tab context menu routes split up, down, left, and close', (
    tester,
  ) async {
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Terminal 1'),
      _tab('tab-2', title: 'Terminal 2'),
    ];

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: .single(
        workspaceId: _workspaceId,
        groupId: 'group-a',
        tabIds: tabs.map((tab) => tab.id).toList(),
      ),
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
    );

    for (final label in <String>['Split Up', 'Split Down', 'Split Left']) {
      await _openTabContextMenu(tester, 'Terminal 2');
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await _openTabContextMenu(tester, 'Terminal 2');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(
      splitGroups,
      containsAll(<_SplitGroupAction>[
        const _SplitGroupAction('group-a', .up),
        const _SplitGroupAction('group-a', .down),
        const _SplitGroupAction('group-a', .left),
      ]),
    );
    expect(closedTabs, <String>['tab-2']);
  });

  testWidgets('active-tab fallback picks the first available tab', (
    tester,
  ) async {
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Terminal 1'),
      _tab('tab-2', title: 'Terminal 2'),
    ];

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout(
        workspaceId: _workspaceId,
        root: .leaf('group-a'),
        groups: <String, WorkbenchPaneGroup>{
          'group-a': WorkbenchPaneGroup(
            id: 'group-a',
            tabIds: tabs.map((tab) => tab.id).toList(),
            activeTabId: 'missing-tab',
          ),
        },
        activeGroupId: 'group-a',
      ),
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
    );

    expect(
      find.byKey(const ValueKey<String>('terminal-tab-1')),
      findsOneWidget,
    );
    expect(terminalRuntime.requestedTabIds, contains('tab-1'));
  });

  testWidgets('terminal tab chips show agent status dots', (tester) async {
    final tab = _tab('tab-1', title: 'Terminal');

    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[tab],
      terminalRuntime: terminalRuntime,
      layout: .single(workspaceId: _workspaceId, tabIds: <String>[tab.id]),
      agentStatuses: <String, AgentStatusEntry>{
        tab.terminalSessionId: _agentStatus(tab, state: .waiting),
      },
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
    );

    expect(find.byType(AleraStatusDot), findsOneWidget);
  });

  testWidgets('editor tabs use file icons in the chip', (tester) async {
    final terminalTab = _tab('tab-1', title: 'Terminal');
    final editorTab = _tab(
      'tab-2',
      title: 'main.dart',
      kind: .editor,
      filePath: 'lib/main.dart',
    );

    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[terminalTab, editorTab],
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout(
        workspaceId: _workspaceId,
        root: .leaf('group-a'),
        groups: <String, WorkbenchPaneGroup>{
          'group-a': WorkbenchPaneGroup(
            id: 'group-a',
            tabIds: <String>[terminalTab.id, editorTab.id],
            activeTabId: terminalTab.id,
          ),
        },
        activeGroupId: 'group-a',
      ),
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
    );

    final icon = tester.widget<AleraFileIcon>(find.byType(AleraFileIcon));
    expect(icon.kind, AleraFileIconKind.file);
    expect(icon.pathOrName, 'lib/main.dart');
  });

  testWidgets('markdown viewer tabs use file icons in the chip', (
    tester,
  ) async {
    final terminalTab = _tab('tab-1', title: 'Terminal');
    final viewerTab = _tab(
      'tab-2',
      title: 'readme.md',
      kind: .markdownViewer,
      filePath: 'docs/readme.md',
    );

    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[terminalTab, viewerTab],
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout(
        workspaceId: _workspaceId,
        root: .leaf('group-a'),
        groups: <String, WorkbenchPaneGroup>{
          'group-a': WorkbenchPaneGroup(
            id: 'group-a',
            tabIds: <String>[terminalTab.id, viewerTab.id],
            activeTabId: terminalTab.id,
          ),
        },
        activeGroupId: 'group-a',
      ),
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
    );

    final fileIcons = tester.widgetList<AleraFileIcon>(
      find.byType(AleraFileIcon),
    );
    expect(fileIcons.single.kind, AleraFileIconKind.file);
    expect(fileIcons.single.pathOrName, 'docs/readme.md');
  });

  testWidgets('git diff tabs use source control icon and editor width', (
    tester,
  ) async {
    final terminalTab = _tab('tab-1', title: 'Terminal');
    final editorTab = _tab(
      'tab-2',
      title: 'very_long_editor_file_name.dart',
      kind: .editor,
      filePath: 'lib/very_long_editor_file_name.dart',
    );
    final gitDiffTab = _tab(
      'tab-3',
      title: 'very_long_git_diff_file_name.dart',
      kind: .gitDiff,
      filePath: 'lib/very_long_git_diff_file_name.dart',
    );

    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[terminalTab, editorTab, gitDiffTab],
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout(
        workspaceId: _workspaceId,
        root: .leaf('group-a'),
        groups: <String, WorkbenchPaneGroup>{
          'group-a': WorkbenchPaneGroup(
            id: 'group-a',
            tabIds: <String>[terminalTab.id, editorTab.id, gitDiffTab.id],
            activeTabId: terminalTab.id,
          ),
        },
        activeGroupId: 'group-a',
      ),
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
      size: const Size(720, 280),
    );

    expect(find.byIcon(AleraIcons.gitBranch), findsOneWidget);
    expect(_tabTitleMaxWidth(tester, editorTab.title), 180);
    expect(_tabTitleMaxWidth(tester, gitDiffTab.title), 180);
  });
}

double _tabTitleMaxWidth(WidgetTester tester, String title) {
  final box = tester.widget<ConstrainedBox>(
    find.ancestor(of: find.text(title), matching: find.byType(ConstrainedBox)),
  );
  return box.constraints.maxWidth;
}
