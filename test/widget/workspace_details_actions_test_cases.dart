part of 'workspace_details_overlay_test.dart';

Finder _hostOptions() => find.byWidgetPredicate(
  (widget) =>
      widget is Tooltip &&
      widget.message == '${Platform.localHostname} Options',
);

void _registerWorkspaceDetailsActionTests() {
  testWidgets('the host menu offers the sidebar workspace actions', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOverlay(
      tester,
      const Size(1000, 800),
      workbench: _relatedState(const []).copyWith(supportsArchive: true),
    );
    await tester.tap(_hostOptions());
    await tester.pumpAndSettle();
    for (final label in ['Hand On', 'Rename', 'Sleep', 'Archive', 'Remove']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Hand Off'), findsNothing);
  });

  testWidgets('Sleep confirms before sleeping the workspace', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOverlay(
      tester,
      const Size(1000, 800),
      workbench: _relatedState(const []),
    );
    await tester.tap(_hostOptions());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();
    expect(find.text('Sleep Workspace?'), findsOneWidget);
    expect(_workbenchOf(tester).sleptWorkspaces, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Sleep'));
    await tester.pumpAndSettle();
    expect(_workbenchOf(tester).sleptWorkspaces, ['w']);
  });

  testWidgets('Archive is hidden when the host cannot archive', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOverlay(
      tester,
      const Size(1000, 800),
      workbench: _relatedState(const []),
    );
    await tester.tap(_hostOptions());
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsNothing);
  });
}
