import 'package:alera/src/features/pull_requests/domain/pull_request_ship_scope.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_composer.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_ship_dialog.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_git_backend.dart';

Future<void> _pumpComposer(
  WidgetTester tester, {
  required PullRequestShipCallback onShip,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitBackendProvider.overrideWithValue(FakeGitBackend()),
        settingsControllerProvider.overrideWithValue(.defaults),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: PullRequestComposer(
              repoPath: '/repo',
              headBranch: 'feat/ship',
              baseBranches: const <String>['main'],
              suggestedBaseBranch: 'main',
              canCreate: true,
              busy: false,
              suggestedReview: null,
              createAction: .publish,
              onCreate: (_) {},
              onShip: onShip,
              onLink: (_) {},
              onCreateActionChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('ship dialog orders staged, all, then cancel', (tester) async {
    PullRequestShipScope? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<PullRequestShipScope>(
                  context: context,
                  builder: (_) => const PullRequestShipDialog(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final stagedTop = tester.getTopLeft(
      find.byKey(const Key('ship-staged-changes-button')),
    );
    final allTop = tester.getTopLeft(
      find.byKey(const Key('ship-all-changes-button')),
    );
    final cancelTop = tester.getTopLeft(
      find.byKey(const Key('ship-cancel-button')),
    );
    expect(stagedTop.dy, lessThan(allTop.dy));
    expect(allTop.dy, lessThan(cancelTop.dy));

    await tester.tap(find.byKey(const Key('ship-all-changes-button')));
    await tester.pumpAndSettle();
    expect(result, PullRequestShipScope.all);
  });

  testWidgets('ship button opens dialog and forwards the scope', (
    tester,
  ) async {
    PullRequestShipScope? shippedScope;
    await _pumpComposer(
      tester,
      onShip: ({required baseBranch, required draft, required scope}) async {
        shippedScope = scope;
      },
    );

    await tester.tap(find.byKey(const Key('pull-request-ship-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ship-staged-changes-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ship-staged-changes-button')));
    await tester.pumpAndSettle();
    expect(shippedScope, PullRequestShipScope.staged);
  });

  testWidgets('cancelling the ship dialog ships nothing', (tester) async {
    var shipped = false;
    await _pumpComposer(
      tester,
      onShip: ({required baseBranch, required draft, required scope}) async {
        shipped = true;
      },
    );

    await tester.tap(find.byKey(const Key('pull-request-ship-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ship-cancel-button')));
    await tester.pumpAndSettle();
    expect(shipped, isFalse);
  });
}
