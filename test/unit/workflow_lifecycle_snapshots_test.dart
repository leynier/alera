import 'package:alera/src/features/orchestration/domain/workflow_cleanup_snapshot.dart';
import 'package:alera/src/features/orchestration/domain/workflow_run_controls.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workflow_cleanup_fixture.dart';
import '../support/workflow_controls_fixture.dart';

void main() {
  test('recipe origins remain explicit and unknown origins are rejected', () {
    for (final (source, label) in [
      ({'origin': 'builtIn'}, 'Built-in'),
      ({'origin': 'personal'}, 'Personal'),
      (
        {'origin': 'project', 'path': '.alera/workflows/feature.yaml'},
        'Project: .alera/workflows/feature.yaml',
      ),
    ]) {
      final snapshot = WorkflowRunControls.fromJson({
        ...workflowControlsFixture(),
        'recipeSource': source,
      });
      expect(snapshot.recipeOrigin, label);
    }
    expect(
      () => WorkflowRunControls.fromJson({
        ...workflowControlsFixture(),
        'recipeSource': {'origin': 'remote'},
      }),
      throwsFormatException,
    );
  });

  test(
    'claimed cleanup resources retain state and cannot be selected again',
    () {
      final item = (cleanupPreviewFixture()['items']! as List).single as Map;
      for (final state in WorkflowCleanupState.values) {
        final resource = WorkflowCleanupResource.fromJson({
          'identity': item['identity'],
          'phase': 'ready',
          'registered': state != WorkflowCleanupState.retired,
          'retired': state == WorkflowCleanupState.retired,
          'cleanupId': 'cleanup',
          'cleanupState': state.name,
        });
        expect(resource.cleanupState, state);
        expect(resource.cleanupId, 'cleanup');
        expect(resource.canSelect, false);
        expect(resource.identity.runId, 'run');
      }
    },
  );
}
