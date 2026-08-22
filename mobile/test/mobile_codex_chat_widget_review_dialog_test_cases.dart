part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexReviewDialogTests() {
  testWidgets('mobile review searches branches and starts a detached review', (
    tester,
  ) async {
    final codex = FakeMobileCodexClient(
      responses: const <String, Map<String, Object?>>{
        'codex.review.branches': <String, Object?>{
          'branches': <String>['main', 'develop', 'feature/mobile-review'],
          'currentBranch': 'develop',
        },
      },
    );
    addTearDown(codex.dispose);
    await _pumpScreen(tester, client: codex, hostId: 'host-review-branches');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/review');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('mobile-codex-review-target')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('mobile-codex-review-option-baseBranch'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('mobile-codex-review-branch')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('mobile-codex-review-branch-search')),
      'feature',
    );
    await tester.pump();
    expect(find.text('feature/mobile-review'), findsOneWidget);
    await tester.tap(find.text('feature/mobile-review'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('mobile-codex-review-delivery')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('mobile-codex-review-option-detached')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('mobile-codex-review-submit')),
    );
    await tester.pumpAndSettle();

    final review = codex.calls.lastWhere(
      (call) => call.type == 'codex.review.start',
    );
    expect(review.payload, <String, Object?>{
      'tabId': 'tab-host-review-branches',
      'target': <String, Object?>{
        'type': 'baseBranch',
        'branch': 'feature/mobile-review',
      },
      'delivery': 'detached',
    });
  });
}
