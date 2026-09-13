import 'package:alera/src/features/projects/infra/runtime_project_branch_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'branch catalog binds the response to the selected project and host',
    () async {
      final client = RuntimeProjectBranchClient((verb, payload) async {
        expect(verb, 'project.branches.list');
        expect(payload, {'projectId': 'project', 'hostId': 'ssh'});
        return {
          'projectId': 'project',
          'hostId': 'ssh',
          'branches': ['remote-only', 'origin/topic'],
          'localBranches': ['remote-only'],
        };
      });
      final value = await client.load('project', 'ssh');
      expect(value.branches, ['remote-only', 'origin/topic']);
      expect(value.localBranches, {'remote-only'});
    },
  );

  test(
    'legacy or mismatched replies cannot substitute local branches',
    () async {
      for (final response in [
        {
          'projectId': 'project',
          'branches': ['main'],
          'localBranches': ['main'],
        },
        {
          'projectId': 'project',
          'hostId': 'local',
          'branches': ['main'],
          'localBranches': ['main'],
        },
        {
          'projectId': 'other',
          'hostId': 'ssh',
          'branches': ['main'],
          'localBranches': ['main'],
        },
      ]) {
        final client = RuntimeProjectBranchClient((_, _) async => response);
        await expectLater(client.load('project', 'ssh'), throwsStateError);
      }
    },
  );
}
