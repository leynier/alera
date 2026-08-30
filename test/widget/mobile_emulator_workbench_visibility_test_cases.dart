part of 'mobile_emulator_surface_test.dart';

void _registerWorkbenchEmulatorVisibilityTests() {
  for (final quickReturn in [false, true]) {
    testWidgets(
      'retained workbench ${quickReturn ? 'reuses' : 'reacquires'} emulator capture',
      (tester) async {
        final client = _SurfaceRuntimeHostClient();
        final service = MobileEmulatorService(client);
        final leases = MobileEmulatorLeaseCoordinator(service);
        final runtime = XtermTerminalRuntime();
        final visible = ValueNotifier(true);
        addTearDown(visible.dispose);
        addTearDown(runtime.dispose);
        addTearDown(leases.dispose);
        addTearDown(service.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              agentTitleAvailableProvider.overrideWith((ref) async => false),
              mobileEmulatorServiceProvider.overrideWithValue(service),
              mobileEmulatorLeaseCoordinatorProvider.overrideWithValue(leases),
            ],
            child: MaterialApp(
              theme: buildAleraDarkTheme(),
              home: Scaffold(
                body: ValueListenableBuilder(
                  valueListenable: visible,
                  builder: (context, value, child) => Visibility(
                    visible: value,
                    maintainState: true,
                    child: child!,
                  ),
                  child: _emulatorWorkbench(runtime),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(client.acquireRequests, 1);
        expect(client.releaseRequests, 0);
        final state = tester.state(find.byType(WorkspaceWorkbenchView));

        visible.value = false;
        await tester.pump();
        expect(
          find.byType(MobileEmulatorSurface, skipOffstage: false),
          findsNothing,
        );
        expect(
          tester.state(
            find.byType(WorkspaceWorkbenchView, skipOffstage: false),
          ),
          same(state),
        );
        if (!quickReturn) {
          await tester.pump(MobileEmulatorLeaseCoordinator.releaseGrace);
          expect(client.releaseRequests, 1);
        }

        visible.value = true;
        await tester.pump();
        await tester.pump();
        expect(find.byType(MobileEmulatorSurface), findsOneWidget);
        expect(tester.state(find.byType(WorkspaceWorkbenchView)), same(state));
        expect(client.acquireRequests, quickReturn ? 1 : 2);
        await tester.pump(MobileEmulatorLeaseCoordinator.releaseGrace);
        expect(client.releaseRequests, quickReturn ? 0 : 1);
        expect(client.requests, isNot(contains('emulator.stop')));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(MobileEmulatorLeaseCoordinator.releaseGrace);
        expect(client.releaseRequests, quickReturn ? 1 : 2);
      },
    );
  }
}

Widget _emulatorWorkbench(TerminalRuntime runtime) => WorkspaceWorkbenchView(
  project: Project(
    id: _workspace.projectId,
    name: 'Alera',
    repoPath: _workspace.path,
    createdAt: _now,
    updatedAt: _now,
  ),
  workspace: _workspace,
  tabs: [_tab],
  layout: null,
  terminalRuntime: runtime,
  agentStatuses: const {},
  completionAcknowledgements: WorkbenchTabCompletionAcknowledgements(),
  onCreateTab: ({targetGroupId}) async {},
  onCreateBrowserTab: null,
  onOpenEditorTab: ({required relativePath, targetGroupId}) async {},
  onOpenMarkdownViewerTab: ({required relativePath, targetGroupId}) async {},
  onSelectTab: ({required groupId, required tabId}) {},
  onCloseTab: (_) {},
  onCloseTabs: (_) {},
  onRenameTab: ({required tabId, required title}) async {},
  onOpenEditor: (_) async {},
  onOpenMermanPreview: (_) async {},
  onMoveTab: ({
    required tabId,
    required targetGroupId,
    required zone,
    index,
  }) async {},
  onSplitGroup: ({required groupId, required zone}) async {},
  onMergeGroup: ({required groupId}) async {},
  onActivateGroup: ({required groupId}) {},
  onUpdateSplitRatio: ({required nodePath, required ratio}) {},
);
