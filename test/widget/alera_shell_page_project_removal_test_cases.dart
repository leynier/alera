part of 'alera_shell_page_test.dart';

void _registerProjectRemovalDependencyTests() {
  testWidgets(
    'project automation impact requires confirmation even when ordinary confirmation is disabled',
    (tester) async {
      var pauses = 0;
      final state = _linkedWorkbenchState();
      final harness = await _pumpShell(
        tester,
        state: state,
        settings: AleraSettings.defaults.copyWith(
          general: AleraSettings.defaults.general.copyWith(
            confirmProjectRemoval: false,
          ),
        ),
        managedRuntime: _FakeManagedWorkspaceRuntime(
          dependencies: const [
            WorkspaceRemovalDependency(
              id: 'automation',
              name: 'Nightly Check',
              activeRuns: 2,
              requiresPause: true,
            ),
          ],
          onPause: () => pauses++,
        ),
      );
      await tester.tapAt(
        tester.getCenter(find.text('Alera').last),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove Project'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nightly Check: 2 active runs'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Pause And Remove'),
        findsOneWidget,
      );
      expect(pauses, 0);
      expect(harness.runtime.closedWorkspaceIds, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(pauses, 0);
      expect(harness.controller.state.projects, hasLength(1));
      expect(harness.runtime.closedWorkspaceIds, isEmpty);
    },
  );
}
