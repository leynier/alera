import 'package:alera/src/design_system/layout/alera_sectioned_picker.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const List<AleraPickerSection<String>> _sections = <AleraPickerSection<String>>[
  AleraPickerSection<String>(
    title: 'Running Agents',
    emptyMessage: 'No running agents.',
    rows: <AleraPickerRow<String>>[],
  ),
  AleraPickerSection<String>(
    title: 'New Tab',
    rows: <AleraPickerRow<String>>[
      AleraPickerRow<String>(value: 'main', title: 'alera / main'),
      AleraPickerRow<String>(
        value: 'remote',
        title: 'alera / remote',
        subtitle: 'Remote host',
        disabledReason: 'Host is offline.',
      ),
    ],
  ),
  AleraPickerSection<String>(
    title: 'New Worktree',
    rows: <AleraPickerRow<String>>[
      AleraPickerRow<String>(
        value: 'worktree',
        title: 'alera',
        subtitle: 'From main',
      ),
    ],
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required List<String> selections,
  String? selectedValue,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: AleraSectionedPicker<String>(
            sections: _sections,
            selectedValue: selectedValue,
            onSelected: selections.add,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders sections, empty messages and disabled reasons', (
    tester,
  ) async {
    await _pump(tester, selections: <String>[], selectedValue: 'worktree');

    expect(find.text('RUNNING AGENTS'), findsOneWidget);
    expect(find.text('No running agents.'), findsOneWidget);
    expect(find.text('Host is offline.'), findsOneWidget);
    expect(find.text('Remote host'), findsNothing);
    expect(
      find.ancestor(
        of: find.text('alera'),
        matching: find.byWidgetPredicate(
          (widget) => widget is AleraActiveRail && widget.active,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('typing filters rows and hides empty sections', (tester) async {
    await _pump(tester, selections: <String>[]);

    await tester.enterText(find.byType(TextField), 'from main');
    await tester.pump();

    expect(find.text('alera'), findsOneWidget);
    expect(find.text('alera / main'), findsNothing);
    expect(find.text('RUNNING AGENTS'), findsNothing);
    expect(find.text('NEW TAB'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No matches.'), findsOneWidget);
  });

  testWidgets('disabled rows cannot be selected', (tester) async {
    final selections = <String>[];
    await _pump(tester, selections: selections);

    await tester.tap(find.text('alera / remote'));
    await tester.pump();
    expect(selections, isEmpty);

    await tester.tap(find.text('alera / main'));
    await tester.pump();
    expect(selections, <String>['main']);
  });

  testWidgets('arrows skip disabled rows and Enter selects', (tester) async {
    final selections = <String>[];
    await _pump(tester, selections: selections);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selections, <String>['main']);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selections, <String>['main', 'worktree']);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selections, <String>['main', 'worktree', 'main']);
  });
}
