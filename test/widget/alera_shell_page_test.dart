import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/shell/presentation/alera_shell_page.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_folder_opener.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/workspace_workbench_view.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AleraDatabase> openMemoryDb() async {
    return AleraDatabase(executor: NativeDatabase.memory());
  }

  Future<_ShellPumpHarness> pumpShell(
    WidgetTester tester, {
    required WorkbenchState state,
    _FakeTerminalRuntime? terminalRuntime,
    WorkspaceFolderOpener? workspaceFolderOpener,
    _ShellTestWorkbenchController? controller,
    AleraSettings? settings,
  }) async {
    final shellController = controller ?? _ShellTestWorkbenchController(state);
    final runtime = terminalRuntime ?? _FakeTerminalRuntime();
    final settingsController = _ShellSettingsController(
      settings ?? AleraSettings.defaults,
    );
    final db = await openMemoryDb();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aleraDatabaseProvider.overrideWith((ref) async => db),
          workbenchControllerProvider.overrideWith(() => shellController),
          terminalRuntimeProvider.overrideWith((ref) => runtime),
          terminalHostWarmupProvider.overrideWith((ref) {}),
          settingsControllerProvider.overrideWith(() => settingsController),
          if (workspaceFolderOpener != null)
            workspaceFolderOpenerProvider.overrideWith(
              (ref) => workspaceFolderOpener,
            ),
        ],
        child: const MaterialApp(home: AleraShellPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return _ShellPumpHarness(controller: shellController, runtime: runtime);
  }

  testWidgets('shell renders the terminal workbench for the active workspace', (
    tester,
  ) async {
    await pumpShell(tester, state: _populatedWorkbenchState());

    expect(find.byTooltip('New terminal'), findsOneWidget);
    expect(find.text('New terminal'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsOneWidget,
    );
    expect(find.text('No workspace selected'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'WorkbenchStatusBar',
      ),
      findsNothing,
    );
    expect(find.text('/repo/alera'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Add project'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('shell renders split terminal panes for one workspace', (
    tester,
  ) async {
    await pumpShell(tester, state: _splitWorkbenchState());

    expect(find.byTooltip('New terminal'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-2')),
      findsOneWidget,
    );
  });

  testWidgets('dragging a tab to a pane edge creates a directional split', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpShell(tester, state: _stackedWorkbenchState());

    final tabs = find.byWidgetPredicate((widget) => widget is Draggable);
    expect(tabs, findsNWidgets(2));
    expect(find.byTooltip('New terminal'), findsOneWidget);

    final secondTabStart = tester.getTopLeft(tabs.at(1)) + const Offset(24, 20);
    final terminalRect = tester.getRect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-2')),
    );
    final target = Offset(terminalRect.right - 48, terminalRect.center.dy);
    final gesture = await tester.startGesture(secondTabStart);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 96));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byTooltip('New terminal'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-2')),
      findsOneWidget,
    );
  });

  testWidgets('tab context menu exposes split, close, and title actions', (
    tester,
  ) async {
    final harness = await pumpShell(tester, state: _stackedWorkbenchState());

    final tabs = find.byWidgetPredicate((widget) => widget is Draggable);
    await tester.tapAt(
      tester.getCenter(tabs.first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Split up'), findsOneWidget);
    expect(find.text('Split down'), findsOneWidget);
    expect(find.text('Split left'), findsOneWidget);
    expect(find.text('Split right'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Close others'), findsOneWidget);
    expect(find.text('Close tabs to the right'), findsOneWidget);
    expect(find.text('Change title'), findsOneWidget);

    await tester.tap(find.text('Close tabs to the right'));
    await tester.pumpAndSettle();

    expect(harness.runtime.closedTabIds, <String>['tab-2']);
    expect(
      harness.controller.state.tabsFor('workspace-1').map((tab) => tab.id),
      <String>['tab-1'],
    );
  });

  testWidgets('shell shows the empty state when there are no projects', (
    tester,
  ) async {
    await pumpShell(tester, state: const WorkbenchState(bootstrapped: true));

    expect(find.text('No projects yet'), findsAtLeastNWidgets(1));
    expect(find.widgetWithText(FilledButton, 'Add project'), findsOneWidget);
  });

  testWidgets('shell shows the empty state when no workspace is selected', (
    tester,
  ) async {
    await pumpShell(
      tester,
      state: _populatedWorkbenchState().copyWith(activeWorkspaceId: null),
    );

    expect(find.text('Welcome to Alera'), findsOneWidget);
    expect(find.text('Projects & workspaces'), findsOneWidget);
    expect(find.text('Main'), findsAtLeastNWidgets(1));
    expect(find.byTooltip('New terminal'), findsNothing);
  });

  testWidgets('terminal exit closes its tab and activates the remaining tab', (
    tester,
  ) async {
    final harness = await pumpShell(tester, state: _stackedWorkbenchState());

    harness.runtime.emitExit(workspaceId: 'workspace-1', tabId: 'tab-2');
    await tester.pumpAndSettle();

    expect(harness.runtime.closedTabIds, <String>['tab-2']);
    expect(
      harness.controller.state.tabsFor('workspace-1').map((tab) => tab.id),
      <String>['tab-1'],
    );
    expect(harness.controller.state.activeWorkspaceId, 'workspace-1');
    expect(harness.controller.state.activeWorkspaceTab?.id, 'tab-1');
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-2')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsOneWidget,
    );
  });

  testWidgets('terminal exit closes the last tab and deselects the workspace', (
    tester,
  ) async {
    final harness = await pumpShell(tester, state: _populatedWorkbenchState());

    harness.runtime.emitExit(workspaceId: 'workspace-1', tabId: 'tab-1');
    await tester.pumpAndSettle();

    expect(harness.runtime.closedTabIds, <String>['tab-1']);
    expect(harness.controller.state.tabsFor('workspace-1'), isEmpty);
    expect(harness.controller.state.activeWorkspace, isNull);
    expect(find.text('Welcome to Alera'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsNothing,
    );
  });

  testWidgets('terminal exit closes tabs even when no workspace is selected', (
    tester,
  ) async {
    final harness = await pumpShell(
      tester,
      state: _populatedWorkbenchState().copyWith(activeWorkspaceId: null),
    );

    harness.runtime.emitExit(workspaceId: 'workspace-1', tabId: 'tab-1');
    await tester.pumpAndSettle();

    expect(harness.runtime.closedTabIds, <String>['tab-1']);
    expect(harness.controller.state.tabsFor('workspace-1'), isEmpty);
    expect(harness.controller.state.activeWorkspace, isNull);
    expect(find.text('Welcome to Alera'), findsOneWidget);
  });

  testWidgets('clicking new-terminal button focuses the new session', (
    tester,
  ) async {
    final harness = await pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byTooltip('New terminal'));
    // First pump runs the await chain; the second pump runs the
    // post-frame callback that requestFocus() defers to.
    await tester.pump();
    await tester.pump();

    expect(harness.runtime.totalFocusRequests, 1);
  });

  testWidgets('new-terminal shortcut focuses the new session', (tester) async {
    final harness = await pumpShell(tester, state: _populatedWorkbenchState());

    // Focus a descendant so key events bubble up to the global scope.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(harness.runtime.totalFocusRequests, 1);
  });

  testWidgets('split shortcut focuses the new pane terminal', (tester) async {
    final harness = await pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    // Ctrl+Shift+D is the split-right default off macOS.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(harness.runtime.totalFocusRequests, 1);
  });

  testWidgets('workspace context menu shows supported workspace actions', (
    tester,
  ) async {
    final opener = WorkspaceFolderOpener(
      processRunner: _NoopProcessRunner(),
      platform: WorkspaceFolderPlatform.macos,
      directoryExists: (_) async => true,
    );
    await pumpShell(
      tester,
      state: _populatedWorkbenchState(),
      workspaceFolderOpener: opener,
    );

    await tester.tapAt(
      tester.getCenter(find.text('Main').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Open in Finder'), findsOneWidget);
    expect(find.text('Copy path'), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Remove workspace?'), findsNothing);
  });

  testWidgets('workspace context menu sleep closes live sessions only', (
    tester,
  ) async {
    final runtime = _FakeTerminalRuntime();
    await pumpShell(
      tester,
      state: _populatedWorkbenchState(),
      terminalRuntime: runtime,
      workspaceFolderOpener: WorkspaceFolderOpener(
        processRunner: _NoopProcessRunner(),
        platform: WorkspaceFolderPlatform.macos,
        directoryExists: (_) async => true,
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Main').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();

    expect(runtime.closedWorkspaceIds, <String>['workspace-1']);
    expect(find.text('Terminal 1'), findsAtLeastNWidgets(1));
  });

  testWidgets('collapsed rail can reopen the sidebar from a project avatar', (
    tester,
  ) async {
    final harness = await pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byTooltip('Collapse sidebar'));
    await tester.pumpAndSettle();

    expect(harness.controller.state.collapsed, isTrue);
    expect(find.byTooltip('Expand sidebar'), findsOneWidget);

    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();

    expect(harness.controller.state.collapsed, isFalse);
    expect(find.byTooltip('Collapse sidebar'), findsOneWidget);
  });

  testWidgets('sidebar search shows the empty-results state', (tester) async {
    await pumpShell(tester, state: _populatedWorkbenchState());

    await tester.enterText(find.byType(TextField).first, 'missing');
    await tester.pumpAndSettle();

    expect(find.text('No workspaces match "missing"'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();

    expect(find.text('Main'), findsAtLeastNWidgets(1));
  });

  testWidgets('settings button opens the settings dialog', (tester) async {
    await pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('General'), findsWidgets);
  });

  testWidgets('footer add-project button opens the add-project dialog', (
    tester,
  ) async {
    await pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.widgetWithText(OutlinedButton, 'Add project'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Project path'), findsOneWidget);
  });

  testWidgets(
    'new-workspace toolbar button opens the create-workspace dialog',
    (tester) async {
      await pumpShell(tester, state: _populatedWorkbenchState());

      await tester.tap(find.byTooltip('New workspace'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.widgetWithText(FilledButton, 'Create workspace'),
        findsOneWidget,
      );
    },
  );

  testWidgets('tapping a workspace row selects that workspace', (tester) async {
    final harness = await pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tap(find.text('Feature login'));
    await tester.pumpAndSettle();

    expect(harness.controller.state.activeWorkspaceId, 'workspace-2');
  });

  testWidgets('workspace context menu shows folder-open failures as a toast', (
    tester,
  ) async {
    final opener = WorkspaceFolderOpener(
      processRunner: _NoopProcessRunner(),
      platform: WorkspaceFolderPlatform.macos,
      directoryExists: (_) async => false,
    );
    await pumpShell(
      tester,
      state: _populatedWorkbenchState(),
      workspaceFolderOpener: opener,
    );

    await tester.tapAt(
      tester.getCenter(find.text('Main').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in Finder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Main'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('project context menu renames the project', (tester) async {
    final harness = await pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Alera').last),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Project name'),
      '  Renamed Alera  ',
    );
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.controller.state.projects.single.name, 'Renamed Alera');
  });

  testWidgets('workspace context menu renames the workspace', (tester) async {
    final harness = await pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Workspace name'),
      '  Backend API  ',
    );
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      harness.controller.state.workspacesFor('project-1').last.name,
      'Backend API',
    );
  });

  testWidgets('workspace context menu copies the workspace path', (
    tester,
  ) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tapAt(
      tester.getCenter(find.text('Main').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy path'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(copiedText, '/repo/alera');
  });

  testWidgets('sidebar terminal rows can switch workspaces and request focus', (
    tester,
  ) async {
    final harness = await pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tap(find.text('Linked terminal'));
    await tester.pumpAndSettle();

    expect(harness.controller.state.activeWorkspaceId, 'workspace-2');
    expect(
      harness.controller.state.activeTabIdByWorkspace['workspace-2'],
      'tab-2',
    );
    expect(harness.runtime.focusedTabIds, contains('tab-2'));
  });

  testWidgets('closing a sidebar terminal row closes the runtime tab', (
    tester,
  ) async {
    final harness = await pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true, linkedActive: true),
    );

    final terminalRow = find.ancestor(
      of: find.text('Linked terminal'),
      matching: find.byType(InkWell),
    );
    final rowRect = tester.getRect(terminalRow.first);
    await tester.tapAt(Offset(rowRect.right - 12, rowRect.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.runtime.closedTabIds, <String>['tab-2']);
    expect(harness.controller.state.tabsFor('workspace-2'), isEmpty);
    expect(find.text('Linked terminal'), findsNothing);
  });

  testWidgets('linked workspace removal closes runtime and removes the row', (
    tester,
  ) async {
    final harness = await pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.runtime.closedWorkspaceIds, <String>['workspace-2']);
    expect(
      harness.controller.state.workspacesFor('project-1').map((w) => w.id),
      <String>['workspace-1'],
    );
    expect(find.text('Feature login'), findsNothing);
  });

  testWidgets('project removal closes every workspace runtime', (tester) async {
    final harness = await pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Alera').last),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove project'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      harness.runtime.closedWorkspaceIds,
      containsAll(<String>['workspace-1', 'workspace-2']),
    );
    expect(harness.controller.state.projects, isEmpty);
    expect(find.text('No projects yet'), findsAtLeastNWidgets(1));
  });

  testWidgets('shell shows a toast when the workbench state contains an error', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);

    await pumpShell(
      tester,
      state: _populatedWorkbenchState().copyWith(error: 'Workspace failed'),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(events, isNotEmpty);
    expect(events.last.message, 'Workspace failed');
    expect(events.last.tone, AleraToastTone.error);
  });

  testWidgets('clicking a tab activates it in the shell state bridge', (
    tester,
  ) async {
    final harness = await pumpShell(tester, state: _stackedWorkbenchState());

    await tester.tap(find.text('Terminal 1').first);
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.activeTabIdByWorkspace['workspace-1'],
      'tab-1',
    );
  });

  testWidgets('closing a tab from its context menu updates shell state', (
    tester,
  ) async {
    final harness = await pumpShell(tester, state: _stackedWorkbenchState());

    await tester.tapAt(
      tester.getCenter(find.text('Terminal 2').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(harness.runtime.closedTabIds, <String>['tab-2']);
    expect(
      harness.controller.state.tabsFor('workspace-1').map((tab) => tab.id),
      <String>['tab-1'],
    );
  });

  testWidgets('renaming a tab from its context menu updates shell state', (
    tester,
  ) async {
    final harness = await pumpShell(tester, state: _stackedWorkbenchState());

    await tester.tapAt(
      tester.getCenter(find.text('Terminal 1').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change title'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Terminal title'),
      '  Renamed tab  ',
    );
    await tester.tap(find.text('Change title').last);
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.tabsFor('workspace-1').first.title,
      'Renamed tab',
    );
  });

  testWidgets('pane split actions focus the new terminal session', (tester) async {
    final harness = await pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byTooltip('Pane actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();

    expect(harness.runtime.totalFocusRequests, 1);
    expect(harness.controller.state.tabsFor('workspace-1'), hasLength(2));
  });

  testWidgets('closing a split merges the layout in the shell bridge', (
    tester,
  ) async {
    final harness = await pumpShell(tester, state: _splitWorkbenchState());

    await tester.tap(find.byTooltip('Pane actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close split'));
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.layoutFor('workspace-1')!.paneGroupIds,
      hasLength(1),
    );
  });

  testWidgets('dragging the shell split handle updates the layout ratio', (
    tester,
  ) async {
    final harness = await pumpShell(tester, state: _splitWorkbenchState());

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(WorkspaceWorkbenchView)),
    );
    await gesture.moveBy(const Offset(48, 0));
    await gesture.up();
    await tester.pump();

    expect(
      harness.controller.state.layoutFor('workspace-1')!.root.ratio!,
      greaterThan(0.5),
    );
  });

  testWidgets('collapsed sidebar settings button still opens the dialog', (
    tester,
  ) async {
    await pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byTooltip('Collapse sidebar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('General'), findsWidgets);
  });

  testWidgets('collapsed brand row can expand the sidebar', (tester) async {
    final harness = await pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byTooltip('Collapse sidebar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand sidebar'));
    await tester.pumpAndSettle();

    expect(harness.controller.state.collapsed, isFalse);
    expect(find.byTooltip('Collapse sidebar'), findsOneWidget);
  });

  testWidgets('project header quick action opens create workspace dialog', (
    tester,
  ) async {
    await pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byTooltip('New workspace in this project'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.widgetWithText(FilledButton, 'Create workspace'), findsOneWidget);
  });

  testWidgets('project context menu can open the create workspace dialog', (
    tester,
  ) async {
    await pumpShell(tester, state: _linkedWorkbenchState(linkedExpanded: true));

    await tester.tapAt(
      tester.getCenter(find.text('Alera').last),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New workspace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.widgetWithText(FilledButton, 'Create workspace'), findsOneWidget);
  });

  testWidgets('workspace toggle can hide terminal rows', (tester) async {
    final harness = await pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true, linkedActive: true),
    );

    final toggles = find.byTooltip('Hide terminal tabs');
    final workspaceCenter = tester.getCenter(find.text('Feature login').first);
    var toggleIndex = 0;
    var bestDistance = double.infinity;
    final toggleCount = toggles.evaluate().length;
    for (var index = 0; index < toggleCount; index += 1) {
      final distance = (tester.getCenter(toggles.at(index)).dy - workspaceCenter.dy)
          .abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        toggleIndex = index;
      }
    }

    await tester.tap(toggles.at(toggleIndex));
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.viewPrefs.expandedWorkspaceIds.contains(
        'workspace-2',
      ),
      isFalse,
    );
  });

  testWidgets('workspace removal dialog omits branch details when blank', (
    tester,
  ) async {
    final seeded = _linkedWorkbenchState(linkedExpanded: true);
    final workspaces = seeded.workspacesFor('project-1');
    final branchlessState = seeded.copyWith(
      workspacesByProject: <String, List<Workspace>>{
        'project-1': <Workspace>[
          workspaces.first,
          workspaces.last.copyWith(branch: ''),
        ],
      },
    );

    await pumpShell(tester, state: branchlessState);

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(
      find.text('This removes the worktree for "Feature login".'),
      findsOneWidget,
    );
    expect(find.textContaining('deletes branch'), findsNothing);
  });

  testWidgets('project header tap toggles the collapsed project state', (
    tester,
  ) async {
    final harness = await pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tap(find.text('Alera').last);
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.viewPrefs.collapsedProjectIds,
      contains('project-1'),
    );
  });

  testWidgets('folder projects describe their workspaces as local folders', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 5, 22);
    final project = Project(
      id: 'project-folder',
      name: 'Notes',
      repoPath: '/repo/notes',
      createdAt: now,
      updatedAt: now,
      kind: ProjectKind.folder,
    );
    final workspace = Workspace(
      id: 'workspace-folder',
      projectId: project.id,
      name: 'Notes',
      branch: '',
      path: project.repoPath,
      createdAt: now,
      updatedAt: now,
      kind: WorkspaceKind.main,
      status: WorkspaceStatus.active,
    );

    await pumpShell(
      tester,
      state: WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{
          project.id: <Workspace>[workspace],
        },
        activeProjectId: project.id,
        activeWorkspaceId: workspace.id,
        bootstrapped: true,
      ),
    );

    expect(find.textContaining('Local folder'), findsOneWidget);
  });

  testWidgets('flat workspace grouping shows project chips on workspace rows', (
    tester,
  ) async {
    await pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true).copyWith(
        viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
          groupBy: WorkbenchGroupBy.none,
          expandedWorkspaceIds: <String>{'workspace-1', 'workspace-2'},
        ),
      ),
    );

    expect(find.byType(AleraChip), findsAtLeastNWidgets(1));
    expect(find.text('Alera'), findsAtLeastNWidgets(1));
  });

  testWidgets('project rename failures surface an error toast event', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final state = _linkedWorkbenchState(linkedExpanded: true);

    await pumpShell(
      tester,
      state: state,
      controller: _ShellTestWorkbenchController(
        state,
        renameProjectFailure: StateError('rename failed'),
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Alera').last),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Project name'), 'New');
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(events.last.message, 'Bad state: rename failed');
  });

  testWidgets('workspace rename failures surface an error toast event', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final state = _linkedWorkbenchState(linkedExpanded: true);

    await pumpShell(
      tester,
      state: state,
      controller: _ShellTestWorkbenchController(
        state,
        renameWorkspaceFailure: StateError('rename workspace failed'),
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Workspace name'),
      'Renamed',
    );
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(events.last.message, 'Bad state: rename workspace failed');
  });

  testWidgets('workspace removal failures surface an error toast event', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final state = _linkedWorkbenchState(linkedExpanded: true);

    await pumpShell(
      tester,
      state: state,
      controller: _ShellTestWorkbenchController(
        state,
        deleteWorkspaceFailure: StateError('delete workspace failed'),
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(events.last.message, 'Bad state: delete workspace failed');
  });

  testWidgets('project removal failures surface an error toast event', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final state = _linkedWorkbenchState(linkedExpanded: true);

    await pumpShell(
      tester,
      state: state,
      controller: _ShellTestWorkbenchController(
        state,
        removeProjectFailure: StateError('remove project failed'),
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Alera').last),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove project'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(events.last.message, 'Bad state: remove project failed');
  });

  testWidgets('sidebar terminal close failures surface an error toast event', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final state = _linkedWorkbenchState(linkedExpanded: true, linkedActive: true);

    await pumpShell(
      tester,
      state: state,
      controller: _ShellTestWorkbenchController(
        state,
        closeWorkspaceTabFailure: StateError('close tab failed'),
      ),
    );

    final terminalRow = find.ancestor(
      of: find.text('Linked terminal'),
      matching: find.byType(InkWell),
    );
    final rowRect = tester.getRect(terminalRow.first);
    await tester.tapAt(Offset(rowRect.right - 12, rowRect.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(events.last.message, 'Bad state: close tab failed');
  });

  testWidgets('hovering sidebar rows updates their highlight state', (
    tester,
  ) async {
    await pumpShell(tester, state: _linkedWorkbenchState(linkedExpanded: true));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();

    final projectContainer = find
        .ancestor(
          of: find.text('Alera').last,
          matching: find.byType(AnimatedContainer),
        )
        .first;
    final workspaceContainer = find
        .ancestor(
          of: find.text('Feature login').first,
          matching: find.byType(AnimatedContainer),
        )
        .first;
    final terminalContainer = find
        .ancestor(
          of: find.text('Linked terminal'),
          matching: find.byType(AnimatedContainer),
        )
        .first;

    BoxDecoration decorationOf(Finder finder) {
      return tester.widget<AnimatedContainer>(finder).decoration! as BoxDecoration;
    }

    expect(decorationOf(projectContainer).color, Colors.transparent);
    await mouse.moveTo(tester.getCenter(find.text('Alera').last));
    await tester.pumpAndSettle();
    expect(decorationOf(projectContainer).color, AleraTokens.surface);
    await mouse.moveTo(const Offset(0, 0));
    await tester.pumpAndSettle();
    expect(decorationOf(projectContainer).color, Colors.transparent);

    expect(decorationOf(workspaceContainer).color, Colors.transparent);
    await mouse.moveTo(tester.getCenter(find.text('Feature login').first));
    await tester.pumpAndSettle();
    expect(decorationOf(workspaceContainer).color, AleraTokens.surface);
    await mouse.moveTo(const Offset(0, 0));
    await tester.pumpAndSettle();
    expect(decorationOf(workspaceContainer).color, Colors.transparent);

    expect(decorationOf(terminalContainer).color, Colors.transparent);
    await mouse.moveTo(tester.getCenter(find.text('Linked terminal')));
    await tester.pumpAndSettle();
    expect(decorationOf(terminalContainer).color, AleraTokens.surface);
    await mouse.moveTo(const Offset(0, 0));
    await tester.pumpAndSettle();
    expect(decorationOf(terminalContainer).color, Colors.transparent);
  });
}

WorkbenchState _stackedWorkbenchState() {
  final now = DateTime.utc(2026, 5, 22);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
  final workspace = Workspace(
    id: 'workspace-1',
    projectId: project.id,
    name: 'Main',
    branch: 'main',
    path: project.repoPath,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
  final firstTab = WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: workspace.id,
    title: 'Terminal 1',
    createdAt: now,
    updatedAt: now,
  );
  final secondTab = WorkspaceTabRecord(
    id: 'tab-2',
    workspaceId: workspace.id,
    title: 'Terminal 2',
    createdAt: now,
    updatedAt: now,
  );
  return WorkbenchState(
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{
      project.id: <Workspace>[workspace],
    },
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      workspace.id: <WorkspaceTabRecord>[firstTab, secondTab],
    },
    layoutByWorkspace: <String, WorkbenchLayout>{
      workspace.id: WorkbenchLayout.single(
        workspaceId: workspace.id,
        tabIds: <String>[firstTab.id, secondTab.id],
      ),
    },
    activeProjectId: project.id,
    activeWorkspaceId: workspace.id,
    activeTabIdByWorkspace: <String, String>{workspace.id: secondTab.id},
    bootstrapped: true,
  );
}

WorkbenchState _populatedWorkbenchState() {
  final now = DateTime.utc(2026, 5, 22);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
  final workspace = Workspace(
    id: 'workspace-1',
    projectId: project.id,
    name: 'Main',
    branch: 'main',
    path: project.repoPath,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
  final tab = WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: workspace.id,
    title: 'Terminal 1',
    createdAt: now,
    updatedAt: now,
  );
  return WorkbenchState(
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{
      project.id: <Workspace>[workspace],
    },
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      workspace.id: <WorkspaceTabRecord>[tab],
    },
    activeProjectId: project.id,
    activeWorkspaceId: workspace.id,
    activeTabIdByWorkspace: <String, String>{workspace.id: tab.id},
    layoutByWorkspace: <String, WorkbenchLayout>{
      workspace.id: WorkbenchLayout.single(
        workspaceId: workspace.id,
        tabIds: <String>[tab.id],
      ),
    },
    bootstrapped: true,
  );
}

WorkbenchState _splitWorkbenchState() {
  final now = DateTime.utc(2026, 5, 22);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
  final workspace = Workspace(
    id: 'workspace-1',
    projectId: project.id,
    name: 'Main',
    branch: 'main',
    path: project.repoPath,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
  final firstTab = WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: workspace.id,
    title: 'Terminal 1',
    createdAt: now,
    updatedAt: now,
  );
  final secondTab = WorkspaceTabRecord(
    id: 'tab-2',
    workspaceId: workspace.id,
    title: 'Terminal 2',
    createdAt: now,
    updatedAt: now,
  );
  final layout =
      WorkbenchLayout.single(
        workspaceId: workspace.id,
        tabIds: <String>[firstTab.id],
      ).splitWithGroup(
        targetGroupId: WorkbenchLayout.defaultGroupId(workspace.id),
        zone: WorkbenchDropZone.right,
        newGroup: WorkbenchPaneGroup(
          id: 'group-2',
          tabIds: <String>[secondTab.id],
          activeTabId: secondTab.id,
        ),
      );
  return WorkbenchState(
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{
      project.id: <Workspace>[workspace],
    },
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      workspace.id: <WorkspaceTabRecord>[firstTab, secondTab],
    },
    layoutByWorkspace: <String, WorkbenchLayout>{workspace.id: layout},
    activeProjectId: project.id,
    activeWorkspaceId: workspace.id,
    activeTabIdByWorkspace: <String, String>{workspace.id: secondTab.id},
    bootstrapped: true,
  );
}

WorkbenchState _linkedWorkbenchState({
  bool linkedExpanded = false,
  bool linkedActive = false,
}) {
  final now = DateTime.utc(2026, 5, 22);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
  final mainWorkspace = Workspace(
    id: 'workspace-1',
    projectId: project.id,
    name: 'Main',
    branch: 'main',
    path: project.repoPath,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
  final linkedWorkspace = Workspace(
    id: 'workspace-2',
    projectId: project.id,
    name: 'Feature login',
    branch: 'feature/login',
    sourceBranch: 'main',
    path: '/repo/alera-feature-login',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.linked,
    status: WorkspaceStatus.active,
  );
  final mainTab = WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: mainWorkspace.id,
    title: 'Main terminal',
    createdAt: now,
    updatedAt: now,
  );
  final linkedTab = WorkspaceTabRecord(
    id: 'tab-2',
    workspaceId: linkedWorkspace.id,
    title: 'Linked terminal',
    createdAt: now,
    updatedAt: now,
  );
  final activeWorkspace = linkedActive ? linkedWorkspace : mainWorkspace;
  final expandedWorkspaceIds = <String>{mainWorkspace.id};
  if (linkedExpanded || linkedActive) {
    expandedWorkspaceIds.add(linkedWorkspace.id);
  }
  return WorkbenchState(
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{
      project.id: <Workspace>[mainWorkspace, linkedWorkspace],
    },
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      mainWorkspace.id: <WorkspaceTabRecord>[mainTab],
      linkedWorkspace.id: <WorkspaceTabRecord>[linkedTab],
    },
    activeProjectId: project.id,
    activeWorkspaceId: activeWorkspace.id,
    activeTabIdByWorkspace: <String, String>{
      mainWorkspace.id: mainTab.id,
      linkedWorkspace.id: linkedTab.id,
    },
    layoutByWorkspace: <String, WorkbenchLayout>{
      mainWorkspace.id: WorkbenchLayout.single(
        workspaceId: mainWorkspace.id,
        tabIds: <String>[mainTab.id],
      ),
      linkedWorkspace.id: WorkbenchLayout.single(
        workspaceId: linkedWorkspace.id,
        tabIds: <String>[linkedTab.id],
      ),
    },
    viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
      expandedWorkspaceIds: expandedWorkspaceIds,
    ),
    bootstrapped: true,
  );
}

class _ShellTestWorkbenchController extends WorkbenchController {
  _ShellTestWorkbenchController(
    this._bootstrapState, {
    this.renameProjectFailure,
    this.renameWorkspaceFailure,
    this.deleteWorkspaceFailure,
    this.removeProjectFailure,
    this.closeWorkspaceTabFailure,
  });

  final WorkbenchState _bootstrapState;
  final Object? renameProjectFailure;
  final Object? renameWorkspaceFailure;
  final Object? deleteWorkspaceFailure;
  final Object? removeProjectFailure;
  final Object? closeWorkspaceTabFailure;

  @override
  WorkbenchState build() => const WorkbenchState();

  @override
  Future<void> bootstrap() async {
    state = _bootstrapState;
  }

  @override
  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) async {
    state = state.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: workspace.id,
      viewPrefs: state.viewPrefs.copyWith(
        expandedWorkspaceIds: <String>{
          ...state.viewPrefs.expandedWorkspaceIds,
          workspace.id,
        },
      ),
    );
  }

  @override
  void setActiveTab({required String workspaceId, required String tabId}) {
    final layout = state.layoutFor(workspaceId);
    final groupId = layout?.groupIdForTab(tabId);
    state = state.copyWith(
      activeWorkspaceId: workspaceId,
      activeTabIdByWorkspace: <String, String>{
        ...state.activeTabIdByWorkspace,
        workspaceId: tabId,
      },
      layoutByWorkspace: <String, WorkbenchLayout>{
        ...state.layoutByWorkspace,
        if (layout != null && groupId != null)
          workspaceId: layout.setActiveTab(groupId: groupId, tabId: tabId),
      },
    );
  }

  @override
  Future<void> closeWorkspaceTab({
    required Workspace workspace,
    required String tabId,
  }) async {
    if (closeWorkspaceTabFailure case final Object failure) {
      throw failure;
    }
    final remaining = state
        .tabsFor(workspace.id)
        .where((tab) => tab.id != tabId)
        .toList(growable: false);
    final nextActiveTabIdByWorkspace = <String, String>{
      ...state.activeTabIdByWorkspace,
    };
    if (remaining.isEmpty) {
      nextActiveTabIdByWorkspace.remove(workspace.id);
    } else {
      nextActiveTabIdByWorkspace[workspace.id] = remaining.last.id;
    }
    state = state.copyWith(
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        ...state.tabsByWorkspace,
        workspace.id: remaining,
      },
      activeWorkspaceId:
          remaining.isEmpty && state.activeWorkspaceId == workspace.id
          ? null
          : state.activeWorkspaceId,
      activeTabIdByWorkspace: nextActiveTabIdByWorkspace,
      layoutByWorkspace: <String, WorkbenchLayout>{
        ...state.layoutByWorkspace,
        workspace.id: WorkbenchLayout.single(
          workspaceId: workspace.id,
          tabIds: <String>[for (final tab in remaining) tab.id],
        ),
      },
    );
  }

  @override
  Future<void> deleteWorkspace({
    required Project project,
    required Workspace workspace,
    bool deleteBranch = true,
  }) async {
    if (deleteWorkspaceFailure case final Object failure) {
      throw failure;
    }
    final nextWorkspaces = <Workspace>[
      for (final candidate in state.workspacesFor(project.id))
        if (candidate.id != workspace.id) candidate,
    ];
    final nextTabs = <String, List<WorkspaceTabRecord>>{
      for (final entry in state.tabsByWorkspace.entries)
        if (entry.key != workspace.id) entry.key: entry.value,
    };
    final nextLayouts = <String, WorkbenchLayout>{
      for (final entry in state.layoutByWorkspace.entries)
        if (entry.key != workspace.id) entry.key: entry.value,
    };
    final nextActiveTabs = <String, String>{
      for (final entry in state.activeTabIdByWorkspace.entries)
        if (entry.key != workspace.id) entry.key: entry.value,
    };
    final nextExpanded = Set<String>.from(state.viewPrefs.expandedWorkspaceIds)
      ..remove(workspace.id);
    state = state.copyWith(
      workspacesByProject: <String, List<Workspace>>{
        ...state.workspacesByProject,
        project.id: nextWorkspaces,
      },
      tabsByWorkspace: nextTabs,
      layoutByWorkspace: nextLayouts,
      activeTabIdByWorkspace: nextActiveTabs,
      activeWorkspaceId: state.activeWorkspaceId == workspace.id
          ? null
          : state.activeWorkspaceId,
      viewPrefs: state.viewPrefs.copyWith(expandedWorkspaceIds: nextExpanded),
    );
  }

  @override
  Future<void> removeProject(String projectId) async {
    if (removeProjectFailure case final Object failure) {
      throw failure;
    }
    final removedWorkspaceIds = state
        .workspacesFor(projectId)
        .map((workspace) => workspace.id)
        .toSet();
    final nextProjects = <Project>[
      for (final project in state.projects)
        if (project.id != projectId) project,
    ];
    final nextWorkspacesByProject = <String, List<Workspace>>{
      for (final entry in state.workspacesByProject.entries)
        if (entry.key != projectId) entry.key: entry.value,
    };
    final nextTabs = <String, List<WorkspaceTabRecord>>{
      for (final entry in state.tabsByWorkspace.entries)
        if (!removedWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };
    final nextLayouts = <String, WorkbenchLayout>{
      for (final entry in state.layoutByWorkspace.entries)
        if (!removedWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };
    final nextActiveTabs = <String, String>{
      for (final entry in state.activeTabIdByWorkspace.entries)
        if (!removedWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };
    final nextCollapsedProjects = Set<String>.from(
      state.viewPrefs.collapsedProjectIds,
    )..remove(projectId);
    final nextSelectedProjects = Set<String>.from(
      state.viewPrefs.selectedProjectIds,
    )..remove(projectId);
    final nextExpanded = Set<String>.from(state.viewPrefs.expandedWorkspaceIds)
      ..removeAll(removedWorkspaceIds);
    state = state.copyWith(
      projects: nextProjects,
      workspacesByProject: nextWorkspacesByProject,
      tabsByWorkspace: nextTabs,
      layoutByWorkspace: nextLayouts,
      activeTabIdByWorkspace: nextActiveTabs,
      activeProjectId: nextProjects.isEmpty ? null : nextProjects.first.id,
      activeWorkspaceId: null,
      viewPrefs: state.viewPrefs.copyWith(
        collapsedProjectIds: nextCollapsedProjects,
        selectedProjectIds: nextSelectedProjects,
        expandedWorkspaceIds: nextExpanded,
      ),
    );
  }

  @override
  Future<void> renameProject({
    required String projectId,
    required String name,
  }) async {
    if (renameProjectFailure case final Object failure) {
      throw failure;
    }
    final trimmed = name.trim();
    state = state.copyWith(
      projects: <Project>[
        for (final project in state.projects)
          if (project.id == projectId)
            project.copyWith(name: trimmed)
          else
            project,
      ],
    );
  }

  @override
  Future<void> renameWorkspace({
    required String workspaceId,
    required String name,
  }) async {
    if (renameWorkspaceFailure case final Object failure) {
      throw failure;
    }
    final trimmed = name.trim();
    final nextByProject = <String, List<Workspace>>{
      for (final entry in state.workspacesByProject.entries)
        entry.key: <Workspace>[
          for (final workspace in entry.value)
            if (workspace.id == workspaceId)
              workspace.copyWith(name: trimmed)
            else
              workspace,
        ],
    };
    state = state.copyWith(workspacesByProject: nextByProject);
  }

  @override
  Future<void> renameWorkspaceTab({
    required String tabId,
    required String title,
  }) async {
    final trimmed = title.trim();
    state = state.copyWith(
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        for (final entry in state.tabsByWorkspace.entries)
          entry.key: <WorkspaceTabRecord>[
            for (final tab in entry.value)
              if (tab.id == tabId) tab.copyWith(title: trimmed) else tab,
          ],
      },
    );
  }

  @override
  void setActiveWorkspaceTab({
    required String workspaceId,
    required String groupId,
    required String tabId,
  }) {
    final layout = state.layoutFor(workspaceId);
    state = state.copyWith(
      activeWorkspaceId: workspaceId,
      activeTabIdByWorkspace: <String, String>{
        ...state.activeTabIdByWorkspace,
        workspaceId: tabId,
      },
      layoutByWorkspace: <String, WorkbenchLayout>{
        ...state.layoutByWorkspace,
        if (layout != null)
          workspaceId: layout.setActiveTab(groupId: groupId, tabId: tabId),
      },
    );
  }
}

class _ShellSettingsController extends SettingsController {
  _ShellSettingsController(this._seed);

  final AleraSettings _seed;

  @override
  AleraSettings build() => _seed;
}

class _ShellPumpHarness {
  const _ShellPumpHarness({required this.controller, required this.runtime});

  final _ShellTestWorkbenchController controller;
  final _FakeTerminalRuntime runtime;
}

class _FakeTerminalRuntime implements TerminalRuntime {
  final Map<String, _FakeTerminalSessionHandle> _sessions =
      <String, _FakeTerminalSessionHandle>{};
  final StreamController<TerminalRuntimeExitEvent> _exitController =
      StreamController<TerminalRuntimeExitEvent>.broadcast();
  final List<String> closedWorkspaceIds = <String>[];
  final List<String> closedTabIds = <String>[];

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _exitController.stream;

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    return _sessions.putIfAbsent(
      tab.id,
      () => _FakeTerminalSessionHandle(workspace: workspace, tab: tab),
    );
  }

  @override
  void closeTab(String tabId) {
    closedTabIds.add(tabId);
    _sessions.remove(tabId)?.dispose();
  }

  /// Total `requestFocus()` calls across every session this runtime created.
  int get totalFocusRequests => _sessions.values.fold<int>(
    0,
    (sum, session) => sum + session.requestFocusCalls,
  );

  /// Tab ids that received at least one `requestFocus()` call.
  Iterable<String> get focusedTabIds => _sessions.entries
      .where((entry) => entry.value.requestFocusCalls > 0)
      .map((entry) => entry.key);

  void emitExit({
    required String workspaceId,
    required String tabId,
    int exitCode = 0,
  }) {
    _exitController.add(
      TerminalRuntimeExitEvent(
        workspaceId: workspaceId,
        tabId: tabId,
        exitCode: exitCode,
      ),
    );
  }

  @override
  void closeWorkspace(String workspaceId) {
    closedWorkspaceIds.add(workspaceId);
    final removed = _sessions.entries
        .where((entry) => entry.value.workspaceId == workspaceId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final tabId in removed) {
      _sessions.remove(tabId)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    unawaited(_exitController.close());
  }
}

class _FakeTerminalSessionHandle extends TerminalSessionHandle {
  _FakeTerminalSessionHandle({required this.workspace, required this.tab});

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  bool _started = false;

  @override
  String get tabId => tab.id;

  @override
  String get workspaceId => workspace.id;

  @override
  String get displayTitle => tab.title;

  @override
  bool get isRunning => _started;

  @override
  bool get isStarting => false;

  @override
  String? get errorMessage => null;

  @override
  Future<void> ensureStarted() async {
    _started = true;
  }

  @override
  Future<void> restart() => ensureStarted();

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return Center(
      key: ValueKey<String>('fake-terminal-${tab.id}'),
      child: Text('Terminal ${tab.title}'),
    );
  }

  int requestFocusCalls = 0;

  @override
  void requestFocus() {
    requestFocusCalls += 1;
  }
}

class _NoopProcessRunner implements ProcessRunner {
  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}
