part of 'workspace_workbench_view_test.dart';

void _registerExperimentalWorkbenchViewTests() {
  testWidgets(
    'Experimental mounts only its selected surface without a tab strip',
    (tester) async {
      final tabs = [
        _tab('primary', title: 'Main Agent'),
        _tab('aux', title: 'Auxiliary Agent'),
      ];
      final layout = _splitLayout(firstTabId: 'primary', secondTabId: 'aux');
      Future<void> pump({required bool experimental, String? id}) =>
          _pumpWorkbenchView(
            tester,
            tabs: tabs,
            layout: layout,
            terminalRuntime: terminalRuntime,
            createdTabs: createdTabs,
            selectedTabs: selectedTabs,
            closedTabs: closedTabs,
            closedTabGroups: closedTabGroups,
            renamedTabs: renamedTabs,
            movedTabs: movedTabs,
            splitGroups: splitGroups,
            mergedGroups: mergedGroups,
            updatedRatios: updatedRatios,
            singleSurface: experimental,
            singleTabId: id,
          );
      await pump(experimental: true, id: 'primary');
      expect(find.byKey(const ValueKey('terminal-primary')), findsOneWidget);
      expect(find.byKey(const ValueKey('terminal-aux')), findsNothing);
      expect(find.text('Main Agent'), findsNothing);
      expect(find.text('Auxiliary Agent'), findsNothing);
      expect(terminalRuntime.visibilityByTab, {'primary': true});
      final primary = terminalRuntime.peekSession('primary');
      await pump(experimental: true, id: 'aux');
      expect(find.byKey(const ValueKey('terminal-aux')), findsOneWidget);
      expect(terminalRuntime.visibilityByTab, {'primary': false, 'aux': true});
      await pump(experimental: false);
      expect(find.byKey(const ValueKey('terminal-primary')), findsOneWidget);
      expect(find.byKey(const ValueKey('terminal-aux')), findsOneWidget);
      expect(
        identical(terminalRuntime.peekSession('primary'), primary),
        isTrue,
      );
      expect(terminalRuntime.visibilityByTab, {'primary': true, 'aux': true});
      await pump(experimental: true, id: 'primary');
      expect(terminalRuntime.visibilityByTab, {'primary': true, 'aux': false});
      expect(createdTabs, isEmpty);
      expect(closedTabs, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
