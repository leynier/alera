import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/badges/alera_keybinding_badge.dart';
import 'package:alera/src/design_system/chat/alera_message_queue.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _queue({
  required List<(String, int)> moves,
  String? editingId,
  VoidCallback? onCancelEdit,
}) => MaterialApp(
  theme: buildAleraDarkTheme(),
  home: Scaffold(
    body: AleraMessageQueue(
      messages: const <AleraQueuedMessageRow>[
        AleraQueuedMessageRow(id: 'a', text: 'First'),
        AleraQueuedMessageRow(id: 'b', text: 'Second'),
        AleraQueuedMessageRow(id: 'c', text: 'Third'),
      ],
      canSteer: true,
      onEdit: (_) async {},
      onRemove: (_) async {},
      onSteer: (_) async {},
      onReorder: (id, index) async => moves.add((id, index)),
      editingId: editingId,
      onCancelEdit: onCancelEdit,
      editShortcutLabel: 'Alt+Up',
      steerShortcutLabel: 'Ctrl+Alt+Enter',
    ),
  ),
);

void main() {
  testWidgets('Alt+Down and Alt+Up move the row that has the focus', (
    tester,
  ) async {
    final moves = <(String, int)>[];
    await tester.pumpWidget(_queue(moves: moves));
    Future<void> altArrow(String row, LogicalKeyboardKey arrow) async {
      final icon = find.descendant(
        of: find.byKey(ValueKey<String>('queue-edit-$row')),
        matching: find.byType(Icon),
      );
      Focus.of(tester.element(icon)).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(arrow);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
    }

    await altArrow('a', LogicalKeyboardKey.arrowDown);
    await altArrow('c', LogicalKeyboardKey.arrowUp);
    // The first row has nowhere to go up to.
    await altArrow('a', LogicalKeyboardKey.arrowUp);
    expect(moves, <(String, int)>[('a', 1), ('c', 1)]);
  });

  testWidgets('dragging the grip onto another row takes its place', (
    tester,
  ) async {
    final moves = <(String, int)>[];
    await tester.pumpWidget(_queue(moves: moves));
    final grip = find.byIcon(AleraIcons.dragHandle);
    expect(grip, findsNWidgets(3));
    final gesture = await tester.startGesture(tester.getCenter(grip.at(2)));
    await gesture.moveTo(tester.getCenter(find.text('First')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(moves, <(String, int)>[('c', 0)]);
  });

  testWidgets('the edited row offers only Cancel Edit', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(
      _queue(
        moves: <(String, int)>[],
        editingId: 'b',
        onCancelEdit: () => cancelled += 1,
      ),
    );
    expect(find.byKey(const ValueKey<String>('queue-edit-b')), findsNothing);
    await tester.tap(find.text('Cancel Edit'));
    expect(cancelled, 1);
    expect(find.text('Steer'), findsNWidgets(2));
  });

  testWidgets('shortcut keycaps sit in the tooltips of the rows they act on', (
    tester,
  ) async {
    await tester.pumpWidget(_queue(moves: <(String, int)>[]));
    final tooltips = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .where((tooltip) => tooltip.richMessage != null)
        .toList();
    String keycap(Tooltip tooltip) {
      final span = tooltip.richMessage! as TextSpan;
      final badge = (span.children!.single as WidgetSpan).child as Padding;
      return (badge.child! as AleraKeybindingBadge).label;
    }

    expect(tooltips.map(keycap), <String>['Ctrl+Alt+Enter', 'Alt+Up']);
  });
}
