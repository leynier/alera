part of 'codex_chat_surface_test.dart';

void registerCodexReviewDialogTests() {
  testWidgets('filters branches and starts a base branch review', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    final git = FakeGitBackend()
      ..sourceBranches = <String>['develop', 'main', 'release/2026'];
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client, gitBackend: git);

    await _openReviewDialog(tester);
    await _chooseReviewTarget(tester, 'Base Branch');

    expect(
      find.byKey(const ValueKey<String>('codex-review-branch')),
      findsOneWidget,
    );
    expect(find.text('develop'), findsOneWidget);
    expect(find.text('main'), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('codex-review-branch')));
    await tester.pumpAndSettle();
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Search Branches',
    );
    expect(search, findsOneWidget);
    await tester.enterText(search, 'release');
    await tester.pump();
    await tester.tap(find.text('release/2026'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('codex-review-submit')));
    await tester.pumpAndSettle();

    expect(client.reviewPayloads.single, <String, Object?>{
      'tabId': 'codex-tab',
      'target': <String, Object?>{
        'type': 'baseBranch',
        'branch': 'release/2026',
      },
      'delivery': 'inline',
    });
  });

  testWidgets('uses a text area for a custom detached review', (tester) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client, gitBackend: FakeGitBackend());

    await _openReviewDialog(tester);
    await _chooseReviewTarget(tester, 'Custom Instructions');

    final submit = find.byKey(const ValueKey<String>('codex-review-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    final instructions = find.descendant(
      of: find.byKey(const ValueKey<String>('codex-review-instructions')),
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(instructions);
    expect(field.minLines, 4);
    expect(field.maxLines, 8);
    await tester.enterText(
      instructions,
      'Focus on lifecycle races.\nIgnore generated files.',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('codex-review-delivery')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detached').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(client.reviewPayloads.single, <String, Object?>{
      'tabId': 'codex-tab',
      'target': <String, Object?>{
        'type': 'custom',
        'instructions': 'Focus on lifecycle races.\nIgnore generated files.',
      },
      'delivery': 'detached',
    });
  });

  testWidgets('requires a SHA and forwards the optional commit title', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client, gitBackend: FakeGitBackend());

    await _openReviewDialog(tester);
    await _chooseReviewTarget(tester, 'Commit');

    final submit = find.byKey(const ValueKey<String>('codex-review-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('codex-review-commit-sha')),
        matching: find.byType(TextField),
      ),
      'abc1234',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('codex-review-commit-title')),
        matching: find.byType(TextField),
      ),
      'Fix the parser',
    );
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(client.reviewPayloads.single['target'], <String, Object?>{
      'type': 'commit',
      'sha': 'abc1234',
      'title': 'Fix the parser',
    });
  });

  testWidgets('keeps review actions visible in a short viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 380));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client, gitBackend: FakeGitBackend());

    await _openReviewDialog(tester);
    await _chooseReviewTarget(tester, 'Custom Instructions');

    expect(
      find.byKey(const ValueKey<String>('codex-review-form-scroll')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('codex-review-submit')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openReviewDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add Photos And Files'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start Review'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey<String>('codex-review-target')), findsOne);
}

Future<void> _chooseReviewTarget(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey<String>('codex-review-target')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
