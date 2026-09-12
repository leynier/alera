import 'dart:async';

import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_check_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _check = ReviewCheck(
  name: 'build',
  status: .completed,
  conclusion: .success,
);

Widget _wrap(
  Future<ReviewCheckDetails?> Function(ReviewCheck check) onLoadDetails,
) {
  return MaterialApp(
    home: Scaffold(
      body: PullRequestCheckList(
        checks: const <ReviewCheck>[_check],
        onOpenUrl: (_) async {},
        onLoadDetails: onLoadDetails,
      ),
    ),
  );
}

void main() {
  testWidgets('expanding a row fetches and renders its details', (
    tester,
  ) async {
    final completer = Completer<ReviewCheckDetails?>();
    var calls = 0;
    await tester.pumpWidget(
      _wrap((check) {
        calls++;
        return completer.future;
      }),
    );

    await tester.tap(find.text('build'));
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(
      ReviewCheckDetails(
        workflow: 'CI',
        event: 'push',
        startedAt: .utc(2026, 7, 15, 10),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('CI'), findsOneWidget);
    expect(find.textContaining('push'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('collapsing hides the details without refetching', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _wrap((check) async {
        calls++;
        return const ReviewCheckDetails(workflow: 'CI');
      }),
    );

    await tester.tap(find.text('build'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CI'), findsOneWidget);

    await tester.tap(find.text('build'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CI'), findsNothing);
    expect(calls, 1);
  });

  testWidgets('shows No Details Available for an empty result', (tester) async {
    await tester.pumpWidget(_wrap((check) async => null));

    await tester.tap(find.text('build'));
    await tester.pumpAndSettle();
    expect(find.text('No details available'), findsOneWidget);
  });

  group('default collapse', () {
    List<ReviewCheck> passing(int count) => <ReviewCheck>[
      for (var index = 0; index < count; index++)
        ReviewCheck(
          name: 'job $index',
          status: .completed,
          conclusion: .success,
        ),
    ];

    Widget wrapChecks(List<ReviewCheck> checks) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PullRequestCheckList(
            checks: checks,
            onOpenUrl: (_) async {},
            onLoadDetails: (_) async => null,
          ),
        ),
      ),
    );

    testWidgets('collapses passing checks when there are many', (tester) async {
      await tester.pumpWidget(
        wrapChecks(<ReviewCheck>[
          ...passing(6),
          const ReviewCheck(
            name: 'lint',
            status: .completed,
            conclusion: .failure,
          ),
        ]),
      );

      expect(find.text('6 successful Checks'), findsOneWidget);
      expect(find.text('job 0'), findsNothing);
      expect(find.text('lint'), findsOneWidget);

      await tester.tap(find.text('6 successful Checks'));
      await tester.pumpAndSettle();
      expect(find.text('job 0'), findsOneWidget);

      await tester.pumpWidget(wrapChecks(passing(7)));
      await tester.pumpAndSettle();
      expect(find.text('job 6'), findsOneWidget);
    });

    testWidgets('keeps a short list expanded', (tester) async {
      await tester.pumpWidget(wrapChecks(passing(5)));

      expect(find.text('job 0'), findsOneWidget);
    });

    testWidgets('applies the default when checks arrive later', (tester) async {
      await tester.pumpWidget(wrapChecks(const <ReviewCheck>[]));
      await tester.pumpWidget(wrapChecks(passing(6)));

      expect(find.text('job 0'), findsNothing);
    });
  });

  testWidgets('renders the error message when loading fails', (tester) async {
    await tester.pumpWidget(
      _wrap((check) async => throw StateError('network down')),
    );

    await tester.tap(find.text('build'));
    await tester.pumpAndSettle();
    expect(find.textContaining('network down'), findsOneWidget);
  });
}
