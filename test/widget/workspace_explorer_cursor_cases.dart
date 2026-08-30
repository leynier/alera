part of 'workspace_explorer_test.dart';

void _registerWorkspaceExplorerCursorTests() {
  testWidgets('hovering the folder expander resolves the click cursor', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _directory('src', hasChildrenHint: true),
      ]
      ..childrenByDirectory['src'] = <native.WorkspaceFileEntry>[
        _file('src/main.dart'),
      ];

    await _pumpExplorer(tester, service);

    final gesture = await tester.createGesture(kind: .mouse);
    await gesture.addPointer(location: .zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    await gesture.moveTo(
      tester.getCenter(find.byIcon(AleraIcons.chevronRight)),
    );
    await tester.pumpAndSettle();

    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
  });
}
