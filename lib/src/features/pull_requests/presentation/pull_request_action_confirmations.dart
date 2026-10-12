import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review_stack.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:flutter/material.dart';

Future<bool> confirmPullRequestMerge(
  BuildContext context, {
  required HostedReview review,
  HostedReviewStack? stack,
  required ReviewMergeMethod method,
}) async {
  final affected = stack
      ?.entriesThrough(review.number)
      .where((entry) => entry.review.state != HostedReviewState.merged)
      .toList();
  return await showDialog<bool>(
        context: context,
        builder: (_) => AleraConfirmDialog(
          title: stack == null
              ? '${method.label} PR #${review.number}?'
              : '${method.label} Stack Through #${review.number}?',
          message: affected == null
              ? 'This will update the pull request on ${review.provider.label}.'
              : 'This will merge these pull requests atomically:\n${affected.map((entry) => '#${entry.review.number}: ${entry.review.title}').join('\n')}\nPull requests above #${review.number} will remain open.',
          confirmLabel: stack == null ? method.label : '${method.label} Stack',
        ),
      ) ==
      true;
}

Future<bool> confirmPullRequestDraftStatus(
  BuildContext context, {
  required HostedReview review,
  required bool draft,
}) async {
  final label = draft ? 'Convert To Draft' : 'Mark Ready For Review';
  return await showDialog<bool>(
        context: context,
        builder: (_) => AleraConfirmDialog(
          title: '$label PR #${review.number}?',
          message: draft
              ? 'This will convert the pull request to draft on ${review.provider.label}.'
              : 'This will mark the pull request as ready for review on ${review.provider.label}.',
          confirmLabel: label,
        ),
      ) ==
      true;
}
