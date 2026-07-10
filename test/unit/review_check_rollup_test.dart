import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:flutter_test/flutter_test.dart';

ReviewCheck _check(
  ReviewCheckStatus status,
  ReviewCheckConclusion conclusion,
) => ReviewCheck(name: 'c', status: status, conclusion: conclusion);

void main() {
  group('deriveReviewChecksRollup', () {
    test('empty list is none', () {
      expect(deriveReviewChecksRollup(const <ReviewCheck>[]),
          ReviewChecksRollup.none);
    });

    test('any failing conclusion dominates as failure', () {
      final checks = <ReviewCheck>[
        _check(ReviewCheckStatus.completed, ReviewCheckConclusion.success),
        _check(ReviewCheckStatus.completed, ReviewCheckConclusion.failure),
        _check(ReviewCheckStatus.inProgress, ReviewCheckConclusion.pending),
      ];
      expect(deriveReviewChecksRollup(checks), ReviewChecksRollup.failure);
    });

    test('running or pending checks yield pending when nothing failed', () {
      final checks = <ReviewCheck>[
        _check(ReviewCheckStatus.completed, ReviewCheckConclusion.success),
        _check(ReviewCheckStatus.inProgress, ReviewCheckConclusion.pending),
      ];
      expect(deriveReviewChecksRollup(checks), ReviewChecksRollup.pending);
    });

    test('all terminal non-failing checks yield success', () {
      final checks = <ReviewCheck>[
        _check(ReviewCheckStatus.completed, ReviewCheckConclusion.success),
        _check(ReviewCheckStatus.completed, ReviewCheckConclusion.skipped),
        _check(ReviewCheckStatus.completed, ReviewCheckConclusion.neutral),
      ];
      expect(deriveReviewChecksRollup(checks), ReviewChecksRollup.success);
    });

    test('cancelled and timedOut count as failure', () {
      expect(
        deriveReviewChecksRollup(<ReviewCheck>[
          _check(ReviewCheckStatus.completed, ReviewCheckConclusion.cancelled),
        ]),
        ReviewChecksRollup.failure,
      );
      expect(
        deriveReviewChecksRollup(<ReviewCheck>[
          _check(ReviewCheckStatus.completed, ReviewCheckConclusion.timedOut),
        ]),
        ReviewChecksRollup.failure,
      );
    });
  });
}
