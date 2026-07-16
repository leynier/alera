import 'dart:async';

import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_check_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _check = ReviewCheck(
  name: 'build',
  status: ReviewCheckStatus.completed,
  conclusion: ReviewCheckConclusion.success,
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
        startedAt: DateTime.utc(2026, 7, 15, 10),
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

  testWidgets('shows No Details Available for an empty result', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap((check) async => null));

    await tester.tap(find.text('build'));
    await tester.pumpAndSettle();
    expect(find.text('No Details Available'), findsOneWidget);
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
