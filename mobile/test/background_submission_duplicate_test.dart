import 'dart:async';

import 'package:alera_mobile/src/features/workbench/application/background_operations.dart';
import 'package:alera_mobile/src/features/workbench/presentation/background_submission.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final bottomSheet in [false, true]) {
    final formKind = bottomSheet ? 'sheet' : 'dialog';
    testWidgets('a duplicate submit cannot pop the route under a $formKind', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final pending = Completer<String?>();
      final starts = <bool>[];
      var writes = 0;
      await _openForm(
        tester,
        container,
        bottomSheet: bottomSheet,
        onSubmit: (context) {
          for (var tap = 0; tap < 2; tap++) {
            starts.add(
              submitInBackground(
                context,
                operationKey: 'workspace/write',
                title: 'Save',
                action: () {
                  writes++;
                  return pending.future;
                },
              ),
            );
          }
        },
      );
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(starts, [true, false]);
      expect(writes, 1);
      expect(find.text('Workspace screen'), findsOneWidget);
      expect(find.text('Home screen'), findsNothing);
      expect(find.text('Submit'), findsNothing);
      expect(find.text('This operation is already running.'), findsOneWidget);
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Workspace screen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a refused $formKind stays open with its draft and can submit later',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final pending = Completer<String?>();
        container
            .read(backgroundOperationsProvider.notifier)
            .submit(
              operationKey: 'workspace/write',
              title: 'Existing write',
              action: () => pending.future,
            );
        var writes = 0;
        final starts = <bool>[];
        await _openForm(
          tester,
          container,
          bottomSheet: bottomSheet,
          onSubmit: (context) {
            starts.add(
              submitInBackground(
                context,
                operationKey: 'workspace/write',
                title: 'Save',
                action: () async {
                  writes++;
                  return null;
                },
              ),
            );
          },
        );
        await tester.enterText(find.byType(TextField), 'Keep my draft');
        await tester.tap(find.text('Submit'));
        await tester.pumpAndSettle();
        expect(starts, [false]);
        expect(writes, 0);
        expect(find.text('Submit'), findsOneWidget);
        expect(find.text('Keep my draft'), findsOneWidget);
        expect(find.text('This operation is already running.'), findsOneWidget);
        pending.complete(null);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Submit'));
        await tester.pumpAndSettle();
        expect(starts, [false, true]);
        expect(writes, 1);
        expect(find.text('Submit'), findsNothing);
        expect(find.text('Workspace screen'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _openForm(
  WidgetTester tester,
  ProviderContainer container, {
  required bool bottomSheet,
  required void Function(BuildContext) onSubmit,
}) async {
  Widget form(BuildContext context) => Material(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const TextField(),
        TextButton(
          onPressed: () => onSubmit(context),
          child: const Text('Submit'),
        ),
      ],
    ),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                const Text('Home screen'),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        body: Column(
                          children: [
                            const Text('Workspace screen'),
                            TextButton(
                              onPressed: () {
                                if (bottomSheet) {
                                  showModalBottomSheet<void>(
                                    context: context,
                                    builder: form,
                                  );
                                } else {
                                  showDialog<void>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      content: SizedBox(
                                        width: 300,
                                        child: form(context),
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: const Text('Open form'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open workspace'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open workspace'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open form'));
  await tester.pumpAndSettle();
}
