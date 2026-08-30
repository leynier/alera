import 'package:alera/src/features/orchestration/domain/run_execution_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RunPolicyStatus', () {
    test('parses every wire value and defaults to none', () {
      expect(RunPolicyStatus.parse('draft'), RunPolicyStatus.draft);
      expect(RunPolicyStatus.parse('approved'), RunPolicyStatus.approved);
      expect(RunPolicyStatus.parse('rejected'), RunPolicyStatus.rejected);
      expect(RunPolicyStatus.parse('none'), RunPolicyStatus.none);
      expect(RunPolicyStatus.parse('who-knows'), RunPolicyStatus.none);
      expect(RunPolicyStatus.parse(null), RunPolicyStatus.none);
    });

    test('only a draft is pending a decision', () {
      expect(RunPolicyStatus.draft.isPending, isTrue);
      expect(RunPolicyStatus.approved.isPending, isFalse);
      expect(RunPolicyStatus.rejected.isPending, isFalse);
      expect(RunPolicyStatus.none.isPending, isFalse);
    });
  });

  group('RunPolicyStage', () {
    test('parses a full stage', () {
      final stage = RunPolicyStage.fromJson(<String, Object?>{
        'id': 'impl',
        'title': 'Implementation',
        'profile': 'Codex Sol',
        'fallbacks': <Object?>['Claude Big', 7],
      });

      expect(stage.id, 'impl');
      expect(stage.profile, 'Codex Sol');
      expect(stage.label, 'Implementation');
      // Non-string fallback entries are dropped rather than stringified.
      expect(stage.fallbacks, <String>['Claude Big']);
    });

    test('falls back to the id when there is no usable title', () {
      const noTitle = RunPolicyStage(id: 'docs', profile: 'Codex Sol');
      expect(noTitle.label, 'docs');

      final blankTitle = RunPolicyStage.fromJson(<String, Object?>{
        'id': 'docs',
        'profile': 'Codex Sol',
        'title': '   ',
      });
      expect(blankTitle.label, 'docs');
    });

    test('tolerates a stage with missing and malformed fields', () {
      final stage = RunPolicyStage.fromJson(<String, Object?>{
        'fallbacks': 'not-a-list',
      });

      expect(stage.id, isEmpty);
      expect(stage.profile, isEmpty);
      expect(stage.title, isNull);
      expect(stage.fallbacks, isEmpty);
    });
  });

  group('RunExecutionPolicy', () {
    test('parses a proposed plan that holds scheduling', () {
      final policy = RunExecutionPolicy.fromJson(<String, Object?>{
        'runId': 'run_1',
        'workspaceId': 'ws',
        'status': 'draft',
        'blocksDispatch': true,
        'updatedAt': '2026-07-25T10:00:00.000Z',
        'policy': <String, Object?>{
          'stallPolicy': 'auto-failover',
          'stages': <Object?>[
            <String, Object?>{'id': 'impl', 'profile': 'Codex Sol'},
            'not-a-stage',
          ],
        },
      });

      expect(policy.runId, 'run_1');
      expect(policy.workspaceId, 'ws');
      expect(policy.status, RunPolicyStatus.draft);
      expect(policy.blocksDispatch, isTrue);
      expect(policy.hasPolicy, isTrue);
      expect(policy.stallPolicy, 'auto-failover');
      expect(policy.stages, hasLength(1));
      expect(policy.updatedAt, DateTime.utc(2026, 7, 25, 10));
    });

    test('a run without a plan needs no decision', () {
      final policy = RunExecutionPolicy.fromJson(<String, Object?>{
        'runId': 'run_1',
        'workspaceId': 'ws',
        'status': 'none',
        'blocksDispatch': false,
        'policy': null,
        'updatedAt': null,
      });

      expect(policy.hasPolicy, isFalse);
      expect(policy.stages, isEmpty);
      expect(policy.stallPolicy, 'ask');
      expect(policy.updatedAt, isNull);
    });

    test('tolerates an empty payload', () {
      final policy = RunExecutionPolicy.fromJson(const <String, Object?>{});

      expect(policy.runId, isEmpty);
      expect(policy.workspaceId, isEmpty);
      expect(policy.status, RunPolicyStatus.none);
      expect(policy.blocksDispatch, isFalse);
      expect(policy.stages, isEmpty);
      expect(policy.updatedAt, isNull);
    });

    test('tolerates a policy whose stages are not a list', () {
      final policy = RunExecutionPolicy.fromJson(<String, Object?>{
        'runId': 'run_1',
        'status': 'approved',
        'policy': <String, Object?>{'stages': 'nope'},
      });

      expect(policy.stages, isEmpty);
      expect(policy.status, RunPolicyStatus.approved);
      expect(policy.hasPolicy, isTrue);
    });

    test('keeps the default constructor usable', () {
      const policy = RunExecutionPolicy(
        runId: 'run_1',
        workspaceId: 'ws',
        status: .approved,
        blocksDispatch: false,
      );

      expect(policy.stages, isEmpty);
      expect(policy.stallPolicy, 'ask');
      expect(policy.updatedAt, isNull);
    });
  });
}
