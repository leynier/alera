import 'dart:ui' show Tristate;

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/buttons/alera_tab_strip.dart';
import 'package:alera/src/design_system/feedback/alera_gate_card.dart';
import 'package:alera/src/design_system/lists/alera_key_value_list.dart';
import 'package:alera/src/design_system/lists/alera_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: buildAleraDarkTheme(),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

const List<AleraGateCardOption> _stageOptions = <AleraGateCardOption>[
  AleraGateCardOption(
    id: 'reject',
    label: 'Reject',
    destructive: true,
    requiresNotes: true,
  ),
  AleraGateCardOption(
    id: 'approve',
    label: 'Approve',
    busyLabel: 'Approving…',
    primary: true,
  ),
];

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(ValueKey<String>(key))).enabled;

void main() {
  group('AleraTabStrip', () {
    testWidgets('reports the tapped tab and marks the selected one', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final selected = <String>[];
      await _pump(
        tester,
        AleraTabStrip<String>(
          items: const <AleraTabStripItem<String>>[
            AleraTabStripItem<String>(value: 'overview', label: 'Overview'),
            AleraTabStripItem<String>(
              value: 'tasks',
              label: 'Tasks',
              badge: '4/9',
            ),
          ],
          selected: 'overview',
          onSelected: selected.add,
        ),
      );

      expect(find.text('4/9'), findsOneWidget);
      await tester.tap(find.text('Tasks'));
      expect(selected, <String>['tasks']);

      final overview = tester.getSemantics(
        find.byKey(const ValueKey<String>('aleraTab:Overview')),
      );
      final tasks = tester.getSemantics(
        find.byKey(const ValueKey<String>('aleraTab:Tasks')),
      );
      expect(overview.flagsCollection.isSelected, Tristate.isTrue);
      expect(tasks.flagsCollection.isSelected, isNot(Tristate.isTrue));
      semantics.dispose();
    });
  });

  group('AleraTimeline', () {
    testWidgets('groups by day, marks open entries and wires actions', (
      tester,
    ) async {
      var resolved = 0;
      await _pump(
        tester,
        AleraTimeline(
          header: const Text('Run Header'),
          entries: <AleraTimelineEntry>[
            AleraTimelineEntry(
              id: 'a',
              day: 'Today',
              time: '14:02',
              title: 'Question asked',
              detail: 'Waiting for an answer.',
              open: true,
              actions: <Widget>[
                TextButton(
                  onPressed: () => resolved++,
                  child: const Text('Resolve'),
                ),
              ],
            ),
            const AleraTimelineEntry(
              id: 'b',
              day: 'Today',
              time: '13:58',
              title: 'Stage passed',
            ),
            const AleraTimelineEntry(
              id: 'c',
              day: 'Yesterday',
              time: '18:40',
              title: 'Run started',
              body: Text('Expanded body'),
            ),
          ],
        ),
      );

      expect(find.text('Run Header'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('YESTERDAY'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('timeline:b')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('timelineMarkerOpen')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timelineMarker')),
        findsNWidgets(2),
      );
      expect(find.text('Waiting for an answer.'), findsOneWidget);
      expect(find.text('Expanded body'), findsOneWidget);

      await tester.tap(find.text('Resolve'));
      expect(resolved, 1);
    });

    testWidgets('shows the empty message between header and footer', (
      tester,
    ) async {
      await _pump(
        tester,
        const AleraTimeline(
          entries: <AleraTimelineEntry>[],
          header: Text('Run Header'),
          footer: Text('Run Footer'),
          emptyMessage: 'Nothing has happened yet.',
        ),
      );

      expect(find.text('Nothing has happened yet.'), findsOneWidget);
      final header = tester.getTopLeft(find.text('Run Header')).dy;
      final empty = tester
          .getTopLeft(find.text('Nothing has happened yet.'))
          .dy;
      final footer = tester.getTopLeft(find.text('Run Footer')).dy;
      expect(header, lessThan(empty));
      expect(empty, lessThan(footer));
    });
  });

  group('AleraGateCard', () {
    testWidgets('an option that requires notes waits for them', (tester) async {
      final calls = <(String, String)>[];
      await _pump(
        tester,
        AleraGateCard(
          kindLabel: 'Stage Gate',
          title: 'Foundation',
          statusLabel: 'Pending',
          statusDetail: 'Asked 2h ago',
          prompt: 'Approve the foundation stage?',
          options: _stageOptions,
          notesLabel: 'Notes (required to reject)',
          onSelected: (id, notes) => calls.add((id, notes)),
        ),
      );

      expect(find.text('STAGE GATE · Foundation'), findsOneWidget);
      expect(find.text('Asked 2h ago'), findsOneWidget);
      expect(_enabled(tester, 'gateOption:reject'), isFalse);
      expect(_enabled(tester, 'gateOption:approve'), isTrue);

      await tester.enterText(
        find.byKey(const ValueKey<String>('gateNotes')),
        '   ',
      );
      await tester.pump();
      expect(_enabled(tester, 'gateOption:reject'), isFalse);

      await tester.enterText(
        find.byKey(const ValueKey<String>('gateNotes')),
        '  Missing tests.  ',
      );
      await tester.pump();
      expect(_enabled(tester, 'gateOption:reject'), isTrue);
      await tester.tap(find.byKey(const ValueKey<String>('gateOption:reject')));
      expect(calls, <(String, String)>[('reject', 'Missing tests.')]);
    });

    testWidgets('a busy option shows its busy label and locks the card', (
      tester,
    ) async {
      await _pump(
        tester,
        AleraGateCard(
          kindLabel: 'Stage Gate',
          statusLabel: 'Pending',
          prompt: 'Approve?',
          options: _stageOptions,
          busyOptionId: 'approve',
          onSelected: (_, _) {},
        ),
      );

      expect(find.text('Approving…'), findsOneWidget);
      expect(_enabled(tester, 'gateOption:approve'), isFalse);
      expect(_enabled(tester, 'gateOption:reject'), isFalse);
    });

    testWidgets('a stale gate asks for a refresh and refuses answers', (
      tester,
    ) async {
      var refreshed = 0;
      await _pump(
        tester,
        AleraGateCard(
          kindLabel: 'Plan Approval',
          statusLabel: 'Pending',
          prompt: 'Approve the plan?',
          options: _stageOptions,
          stale: true,
          onRefresh: () => refreshed++,
          onSelected: (_, _) {},
        ),
      );

      expect(
        find.text(
          'This gate changed while you were reading. Refresh before deciding.',
        ),
        findsOneWidget,
      );
      expect(_enabled(tester, 'gateOption:approve'), isFalse);
      await tester.tap(find.byKey(const ValueKey<String>('gateRefresh')));
      expect(refreshed, 1);
    });

    testWidgets('Other reveals a free-text answer', (tester) async {
      final calls = <(String, String)>[];
      await _pump(
        tester,
        AleraGateCard(
          kindLabel: 'Decision',
          statusLabel: 'Pending',
          prompt: 'Which auth flow?',
          options: const <AleraGateCardOption>[
            AleraGateCardOption(id: 'device', label: 'Device Code'),
          ],
          allowOther: true,
          onSelected: (id, notes) => calls.add((id, notes)),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('gateOtherField')),
        findsNothing,
      );
      await tester.tap(find.text('Other…'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('gateOtherField')),
        findsOneWidget,
      );
      expect(_enabled(tester, 'gateOption:__other__'), isFalse);

      await tester.enterText(
        find.byKey(const ValueKey<String>('gateOtherField')),
        ' Both, behind a flag ',
      );
      await tester.pump();
      await tester.tap(find.text('Send Answer'));
      expect(calls, <(String, String)>[
        (AleraGateCard.otherOptionId, 'Both, behind a flag'),
      ]);
    });
  });

  group('AleraKeyValueList', () {
    late List<String> copied;

    setUp(() {
      copied = <String>[];
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          });
    });

    tearDown(() {
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('renders labels and values and copies a value', (tester) async {
      AleraKeyValue? reported;
      await _pump(
        tester,
        AleraKeyValueList(
          entries: const <AleraKeyValue>[
            AleraKeyValue(label: 'Workflow', value: 'feature-delivery'),
            AleraKeyValue(
              label: 'Run Id',
              value: 'run_01J9',
              mono: true,
              copyable: true,
            ),
          ],
          onCopied: (entry) => reported = entry,
        ),
      );

      expect(find.text('Workflow'), findsOneWidget);
      expect(find.text('feature-delivery'), findsOneWidget);
      expect(find.text('run_01J9'), findsOneWidget);
      expect(find.byTooltip('Copy'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('keyValueCopy:Run Id')),
      );
      await tester.pump();
      expect(copied, <String>['run_01J9']);
      expect(reported?.label, 'Run Id');
    });

    testWidgets('stacks the label above the value when narrow', (tester) async {
      await _pump(
        tester,
        const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 240,
            child: AleraKeyValueList(
              entries: <AleraKeyValue>[
                AleraKeyValue(label: 'Workflow', value: 'feature-delivery'),
              ],
            ),
          ),
        ),
      );

      final label = tester.getTopLeft(find.text('Workflow'));
      final value = tester.getTopLeft(find.text('feature-delivery'));
      expect(value.dy, greaterThan(label.dy));
      expect(value.dx, label.dx);
    });
  });
}
