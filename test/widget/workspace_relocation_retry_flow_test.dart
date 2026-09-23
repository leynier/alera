import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/workbench/presentation/workspace_relocation_retry_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('retry retains the operation ID and requires an explicit click', (
    tester,
  ) async {
    final ids = <String>[];
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: aleraDarkTheme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await runWorkspaceRelocationWithRetry(
                context: context,
                action: 'Hand Off',
                perform: (id) async {
                  ids.add(id);
                  if (ids.length == 1) throw StateError('Response was lost');
                },
              );
            },
            child: const Text('Start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(ids, hasLength(1));
    expect(result, isNull);
    expect(find.text('Retry Hand Off?'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(ids, hasLength(2));
    expect(ids.last, ids.first);
    expect(result, isTrue);
  });

  testWidgets('closing a failure does not retry and a new flow gets a new ID', (
    tester,
  ) async {
    final ids = <String>[];
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: aleraDarkTheme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await runWorkspaceRelocationWithRetry(
                context: context,
                action: 'Hand On',
                perform: (id) async {
                  ids.add(id);
                  throw StateError('Stop the task process first');
                },
              );
            },
            child: const Text('Start'),
          ),
        ),
      ),
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(ids, hasLength(attempt + 1));
    }
    expect(ids.first, isNot(ids.last));
  });
}
