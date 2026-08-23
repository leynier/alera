part of 'alera_shell_page_test.dart';

void _registerAleraShellSidebarMutationTests() {
  testWidgets('project rename applies the mutation and reports success', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final harness = await _pumpShell(
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
      find.widgetWithText(TextField, 'Project Name'),
      '  Renamed Alera  ',
    );
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.controller.state.projects.single.name, 'Renamed Alera');
    expect(events.last.message, 'Project renamed');
    expect(events.last.tone, AleraToastTone.success);
  });

  testWidgets('cancelling a workspace rename leaves it unchanged', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final harness = await _pumpShell(
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
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.workspacesFor('project-1').last.name,
      'Feature login',
    );
    expect(
      events.where((event) => event.message == 'Workspace renamed'),
      isEmpty,
    );
  });

  testWidgets('workspace tag mutation applies and reports success', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final state = _linkedWorkbenchState(linkedExpanded: true);
    final controller = _ShellTestWorkbenchController(state);
    await _pumpShell(tester, state: state, controller: controller);

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Tags'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'New Tag'), 'Review');
    await tester.tap(find.text('Create Tag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.workspaceTags.single.name, 'Review');
    expect(controller.tagUpdates.single.workspaceId, 'workspace-2');
    expect(controller.tagUpdates.single.tagIds, <String>{'tag-1'});
    expect(events.last.message, 'Workspace tags updated');
    expect(events.last.tone, AleraToastTone.success);
  });

  testWidgets('cancelling workspace tag management does not apply changes', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final state = _linkedWorkbenchState(linkedExpanded: true);
    final controller = _ShellTestWorkbenchController(state);
    await _pumpShell(tester, state: state, controller: controller);

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Tags'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(controller.tagUpdates, isEmpty);
    expect(
      events.where((event) => event.message == 'Workspace tags updated'),
      isEmpty,
    );
  });
}
