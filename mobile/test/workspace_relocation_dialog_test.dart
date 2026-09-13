import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_relocation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workspace_relocation_controller_test.dart' show projectTask;

void main() {
  testWidgets(
    'branch mode fields stay independent and decisions revoke confirmation',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAleraMobileDarkTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showWorkspaceRelocationDialog(
                    context,
                    hostId: 'host',
                    workspace: projectTask,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final newBranch = find.byKey(const ValueKey('new-branch'));
      await tester.enterText(newBranch, 'new-topic');
      final consent = find.widgetWithText(
        CheckboxListTile,
        'Confirm Shared Impact',
      );
      await tester.ensureVisible(consent);
      await tester.tap(consent);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(consent).value, isTrue);
      final current = find.widgetWithText(
        CheckboxListTile,
        'Move Current Branch',
      );
      await tester.ensureVisible(current);
      await tester.tap(current);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(consent).value, isFalse);
      expect(newBranch, findsNothing);
      final replacement = find.byKey(const ValueKey('replacement-branch'));
      expect(tester.widget<TextFormField>(replacement).initialValue, isEmpty);
      final changes = find.widgetWithText(
        CheckboxListTile,
        'Move All Transferable Changes',
      );
      expect(tester.widget<CheckboxListTile>(changes).value, isTrue);
      expect(tester.widget<CheckboxListTile>(changes).onChanged, isNull);
      await tester.enterText(replacement, 'main');
      await tester.tap(current);
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(newBranch).initialValue, 'new-topic');
      expect(tester.widget<CheckboxListTile>(consent).value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
