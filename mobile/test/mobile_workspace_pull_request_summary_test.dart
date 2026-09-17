import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_pull_request_summary.dart';
import 'package:alera_mobile/src/features/workbench/presentation/mobile_workspace_pull_request_status_icon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MobileWorkspacePullRequestSummary.fromJson', () {
    test('maps the runtime payload fields', () {
      final summary = MobileWorkspacePullRequestSummary.fromJson(
        <String, Object?>{
          'workspaceId': 'ws-1',
          'number': 12,
          'title': 'Add fork indicators',
          'url': 'https://github.com/leynier/alera/pull/12',
          'state': 'draft',
          'mergeable': 'CONFLICTING',
          'checksRollup': 'failure',
          'pendingCheckCount': 1,
          'failedCheckCount': 4,
          'failingCheckNames': <String>['build', 'test', 'lint'],
        },
      );

      expect(summary.workspaceId, 'ws-1');
      expect(summary.number, 12);
      expect(summary.state, MobileWorkspacePullRequestState.draft);
      expect(
        summary.mergeable,
        MobileWorkspacePullRequestMergeable.conflicting,
      );
      expect(
        summary.checksRollup,
        MobileWorkspacePullRequestChecksRollup.failure,
      );
      expect(summary.checksFailed, isTrue);
      expect(summary.hasMergeConflict, isFalse);
      expect(summary.failedCheckCount, 4);
      expect(summary.failingCheckNames, <String>['build', 'test', 'lint']);
    });

    test('open conflicting review reports a merge conflict', () {
      final summary = MobileWorkspacePullRequestSummary.fromJson(
        <String, Object?>{
          'workspaceId': 'ws-2',
          'number': 3,
          'state': 'open',
          'mergeable': 'CONFLICTING',
        },
      );

      expect(summary.hasMergeConflict, isTrue);
    });

    test('unknown fields fall back to open and none', () {
      final summary = MobileWorkspacePullRequestSummary.fromJson(
        <String, Object?>{'workspaceId': 'ws-3', 'number': 1},
      );

      expect(summary.state, MobileWorkspacePullRequestState.open);
      expect(summary.checksRollup, MobileWorkspacePullRequestChecksRollup.none);
      expect(summary.checksPending, isFalse);
    });
  });

  group('mobileWorkspacePullRequestStatusTooltip', () {
    test('describes failing checks with hidden overflow', () {
      final summary = MobileWorkspacePullRequestSummary.fromJson(
        <String, Object?>{
          'workspaceId': 'ws-1',
          'number': 7,
          'title': 'Ship it',
          'state': 'open',
          'checksRollup': 'failure',
          'failedCheckCount': 5,
          'failingCheckNames': <String>['build', 'test', 'lint'],
        },
      );

      expect(
        mobileWorkspacePullRequestStatusTooltip(summary),
        'PR #7: Ship it\nChecks failed\nbuild, test, lint, +2 more',
      );
    });

    test('reports running checks and ready to merge', () {
      final pending = MobileWorkspacePullRequestSummary.fromJson(
        <String, Object?>{
          'workspaceId': 'ws-1',
          'number': 8,
          'state': 'open',
          'mergeable': 'MERGEABLE',
          'checksRollup': 'pending',
          'pendingCheckCount': 2,
        },
      );
      expect(
        mobileWorkspacePullRequestStatusTooltip(pending),
        'PR #8: \n2 checks running',
      );

      final ready = MobileWorkspacePullRequestSummary.fromJson(
        <String, Object?>{
          'workspaceId': 'ws-1',
          'number': 9,
          'state': 'open',
          'mergeable': 'MERGEABLE',
        },
      );
      expect(
        mobileWorkspacePullRequestStatusTooltip(ready),
        'PR #9: \nReady to merge',
      );
    });
  });
}
