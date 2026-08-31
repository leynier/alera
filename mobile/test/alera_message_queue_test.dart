import 'dart:async';
import 'package:alera_mobile/src/design_system/chat/alera_message_queue.dart';
import 'package:alera_mobile/src/design_system/chat/alera_message_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'queue expands vertically on a narrow screen and locks duplicate delivery',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var deliveries = 0;
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AleraMessageQueue(
              messages: [
                for (var i = 0; i < 30; i++)
                  AleraQueuedMessageRow(
                    id: '$i',
                    text: i == 1 ? '' : 'Message $i ${'long text ' * 30}',
                    attachmentCount: i == 1 ? 2 : 0,
                  ),
              ],
              canSteer: true,
              paused: true,
              onTogglePaused: () {},
              onEdit: (_) async {},
              onRemove: (_) async {},
              onSteer: (_) {
                deliveries++;
                return pending.future;
              },
            ),
          ),
        ),
      );
      expect(find.text('Steer'), findsNWidgets(3));
      expect(find.text('Attachment'), findsOneWidget);
      expect(find.text('Resume Queue'), findsOneWidget);
      await tester.tap(find.text('Steer').first);
      await tester.pump();
      expect(find.text('Sending'), findsOneWidget);
      await tester.tap(find.text('Sending'));
      expect(deliveries, 1);
      pending.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand Queue'));
      await tester.pumpAndSettle();
      expect(find.text('Steer'), findsNWidgets(30));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a save conflict leaves the edited text and confirmation visible',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AleraMessageEditor(
            text: 'Original',
            restartsHistory: true,
            attachmentCount: 2,
            onSave: (_) async => 'The message changed on another client.',
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'My correction');
      await tester.tap(find.text('Save And Restart'));
      await tester.pumpAndSettle();
      expect(find.text('My correction'), findsOneWidget);
      expect(
        find.text('The message changed on another client.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Files and actions already performed are not undone.',
        ),
        findsOneWidget,
      );
      expect(find.text('2 attached items will be preserved.'), findsOneWidget);
    },
  );
}
