import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summarizes empty, successful, singular, and plural setup failures', () {
    expect(WorktreeSetupReport.empty.isEmpty, isTrue);
    expect(WorktreeSetupReport.empty.summary, 'No Setup Actions Configured');

    const success = WorktreeSetupReport(
      steps: <WorktreeSetupStepReport>[
        WorktreeSetupStepReport(
          kind: WorktreeSetupStepKind.copy,
          label: 'Copy config',
          succeeded: true,
        ),
      ],
    );
    expect(success.hasFailures, isFalse);
    expect(success.summary, 'Setup Completed');

    const oneFailure = WorktreeSetupReport(
      steps: <WorktreeSetupStepReport>[
        WorktreeSetupStepReport(
          kind: WorktreeSetupStepKind.command,
          label: 'Install',
          succeeded: false,
        ),
      ],
    );
    expect(oneFailure.hasFailures, isTrue);
    expect(oneFailure.summary, '1 Setup Action Failed');

    const twoFailures = WorktreeSetupReport(
      steps: <WorktreeSetupStepReport>[
        WorktreeSetupStepReport(
          kind: WorktreeSetupStepKind.command,
          label: 'Install',
          succeeded: false,
        ),
        WorktreeSetupStepReport(
          kind: WorktreeSetupStepKind.config,
          label: 'Configure',
          succeeded: false,
        ),
      ],
    );
    expect(twoFailures.summary, '2 Setup Actions Failed');
  });
}
