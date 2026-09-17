import 'dart:async';

import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/background_setup_job_host.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_relocation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workspace_relocation_controller_test.dart'
    show projectTask, RelocationTestClient;

void main() {
  testWidgets(
    'moving releases the dialog and a failed retry retains its transfer id and choices',
    (tester) async {
      final pending = Completer<void>();
      final client = RelocationTestClient()
        ..pending = pending
        ..failNext = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceClientProvider('host').overrideWith((ref) async => client),
          ],
          child: MaterialApp(
            theme: buildAleraMobileDarkTheme(),
            builder: (context, child) =>
                Stack(children: [child!, const BackgroundSetupJobHost()]),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
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
      await tester.enterText(find.byKey(const ValueKey('new-branch')), 'topic');
      final consent = find.widgetWithText(
        CheckboxListTile,
        'Confirm Shared Impact',
      );
      await tester.ensureVisible(consent);
      await tester.tap(consent);
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Hand Off'));
      await tester.tap(find.widgetWithText(FilledButton, 'Hand Off'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(WorkspaceRelocationDialog), findsNothing);
      expect(find.text('You can keep using the app.'), findsOneWidget);
      expect(client.requests, hasLength(1));
      final transferId = client.requests.single['id'];
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Response lost'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('new-branch')))
            .initialValue,
        'topic',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Hand Off'));
      await tester.tap(find.widgetWithText(FilledButton, 'Hand Off'));
      await tester.pumpAndSettle();
      expect(client.requests, hasLength(2));
      expect(client.requests.last['id'], transferId);
      expect(tester.takeException(), isNull);
    },
  );

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
