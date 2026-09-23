import 'package:alera_mobile/src/features/workbench/presentation/pull_request_link_create_sheets.dart';
import 'package:alera_mobile/src/features/workbench/presentation/background_setup_job_host.dart';
import 'package:alera_mobile/src/features/workbench/application/background_operations.dart';

import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/workbench/presentation/background_operation_cards.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_ship_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Ship closes immediately, survives navigation, and restores choices on failure',
    (tester) async {
      final completion = Completer<String?>();
      var calls = 0;
      MobilePullRequestShipInput? submitted;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAleraMobileDarkTheme(),
            builder: (context, child) => Stack(
              children: [
                child!,
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: BackgroundOperationCards(),
                ),
              ],
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () => showShipPullRequestSheet(
                        context,
                        headBranch: 'feature',
                        baseBranches: const ['main'],
                        suggestedBaseBranch: 'main',
                        onSubmit: (input) {
                          calls++;
                          submitted = input;
                          return completion.future;
                        },
                      ),
                      child: const Text('Open Ship'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const Scaffold(body: Text('Another workspace')),
                        ),
                      ),
                      child: const Text('Navigate'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Ship'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Staged Changes'));
      await tester.tap(find.text('Create As Draft'));
      await tester.tap(find.widgetWithText(FilledButton, 'Ship'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ShipPullRequestSheet), findsNothing);
      expect(find.text('You can keep using the app.'), findsOneWidget);
      expect(calls, 1);
      await tester.tap(find.text('Navigate'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      completion.complete('The commit succeeded, but the push failed.');
      await tester.pumpAndSettle();
      expect(find.text('Another workspace'), findsOneWidget);
      expect(
        find.text('The commit succeeded, but the push failed.'),
        findsOneWidget,
      );
      expect(calls, 1);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(ShipPullRequestSheet), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {true},
      );
      expect(submitted?.baseBranch, 'main');
      expect(submitted?.draft, isTrue);
      expect(submitted?.stagedOnly, isTrue);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed PR creation retains the complete draft for review', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAleraMobileDarkTheme(),
          builder: (context, child) =>
              Stack(children: [child!, const BackgroundSetupJobHost()]),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCreatePullRequestSheet(
                  context,
                  headBranch: 'feature',
                  baseBranches: const ['main'],
                  suggestedBaseBranch: 'main',
                  onSubmit: (_) async => 'Offline',
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
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'My title');
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'My description',
    );
    await tester.tap(find.text('Create As Draft'));
    await tester.tap(find.widgetWithText(FilledButton, 'Create Pull Request'));
    await tester.pumpAndSettle();
    expect(find.byType(CreatePullRequestSheet), findsNothing);
    expect(find.text('Offline'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('My title'), findsOneWidget);
    expect(find.text('My description'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('many pending operations keep bottom navigation usable', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final pending = Completer<String?>();
    var navigations = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAleraMobileDarkTheme(),
          builder: (context, child) =>
              Stack(children: [child!, const BackgroundSetupJobHost()]),
          home: Scaffold(
            body: const Text('Workspace'),
            bottomNavigationBar: TextButton(
              onPressed: () => navigations++,
              child: const Text('Navigate'),
            ),
          ),
        ),
      ),
    );
    final jobs = container.read(backgroundOperationsProvider.notifier);
    for (var i = 0; i < 10; i++) {
      jobs.submit(title: 'Operation $i', action: () => pending.future);
    }
    await tester.pump();
    await tester.tap(find.text('Navigate'));
    expect(navigations, 1);
    expect(tester.takeException(), isNull);
    pending.complete(null);
    await tester.pumpAndSettle();
  });
}
