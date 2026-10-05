import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/shell/presentation/alera_shell_page.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a loading indicator while the database is opening', (
    tester,
  ) async {
    final completer = Completer<AleraDatabase>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aleraDatabaseProvider.overrideWith((ref) => completer.future),
        ],
        child: const MaterialApp(home: AleraShellPage()),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Opening Alera…'), findsOneWidget);
    expect(find.text('Failed to open the local database'), findsNothing);
  });

  testWidgets('shows a friendly error when the database fails to open', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aleraDatabaseProvider.overrideWith(
            (ref) async => throw StateError('boom'),
          ),
        ],
        child: const MaterialApp(home: AleraShellPage()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Failed to open the local database'), findsOneWidget);
    expect(find.textContaining('Bad state: boom'), findsOneWidget);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.text('Copy Details'));
    await tester.pump();
    expect(copied, 'Bad state: boom');
    expect(find.text('Copied'), findsOneWidget);
  });

  test('buildRawLogClipboardText joins lines with newlines', () {
    expect(
      buildRawLogClipboardText(<String>['first line', 'second line']),
      'first line\nsecond line',
    );
  });
}
