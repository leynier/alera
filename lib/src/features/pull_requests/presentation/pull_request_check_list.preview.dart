import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_check_list.dart';
import 'package:flutter/material.dart';

const List<ReviewCheck> _checks = <ReviewCheck>[
  ReviewCheck(
    name: 'build',
    status: ReviewCheckStatus.completed,
    conclusion: ReviewCheckConclusion.success,
    url: 'https://example.com/build',
  ),
  ReviewCheck(
    name: 'tests',
    status: ReviewCheckStatus.inProgress,
    conclusion: ReviewCheckConclusion.pending,
  ),
  ReviewCheck(
    name: 'lint',
    status: ReviewCheckStatus.completed,
    conclusion: ReviewCheckConclusion.failure,
  ),
];

@AleraPreview(name: 'Check list', group: 'PR checks')
Widget pullRequestCheckListPreview() => SizedBox(
  width: 320,
  child: PullRequestCheckList(
    checks: _checks,
    onOpenUrl: (_) async {},
    onLoadDetails: (check) async => ReviewCheckDetails(
      workflow: 'CI',
      event: 'push',
      description: 'Build finished',
      startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      completedAt: DateTime.now(),
    ),
  ),
);
