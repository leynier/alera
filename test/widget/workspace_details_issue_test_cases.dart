part of 'workspace_details_overlay_test.dart';

final _issue = LinkedIssue(
  workspaceId: 'w',
  url: 'https://github.com/leynier/alera/issues/758',
  linkedAt: DateTime.utc(2026),
  number: 758,
  title: 'Link issues to workspaces',
  state: IssueState.open,
);

void _registerWorkspaceDetailsIssueTests() {
  testWidgets('a linked issue gets a row with its actions', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOverlay(tester, const Size(1000, 800), linkedIssue: _issue);
    expect(find.text('#758: Link issues to workspaces'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    await tester.tap(find.byTooltip('#758: Link issues to workspaces Options'));
    await tester.pumpAndSettle();
    expect(find.text('Open Issue In Browser'), findsOneWidget);
    expect(find.text('Change Linked Issue'), findsOneWidget);
    expect(find.text('Unlink Issue'), findsOneWidget);
  });

  testWidgets('without an issue the host menu offers Link Issue', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOverlay(tester, const Size(1000, 800));
    expect(find.textContaining('#758'), findsNothing);
    final host = find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip &&
          widget.message == '${Platform.localHostname} Options',
    );
    await tester.tap(host);
    await tester.pumpAndSettle();
    expect(find.text('Link Issue'), findsOneWidget);
  });
}
