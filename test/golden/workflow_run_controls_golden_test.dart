import 'package:alchemist/alchemist.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/orchestration/domain/workflow_run_controls.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_run_control_panel.dart';
import 'package:flutter/material.dart';

import '../support/workflow_controls_fixture.dart';
import 'alera_golden_harness.dart';

void main() {
  runAleraGoldenTests(() {
    for (final compact in [false, true]) {
      goldenTest(
        'Workflow execution controls ${compact ? "compact" : "desktop"}',
        fileName: 'workflow_run_controls_${compact ? "compact" : "desktop"}',
        constraints: BoxConstraints.tightFor(
          width: compact ? 420 : 760,
          height: compact ? 1300 : 780,
        ),
        builder: () => Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(compact ? 2 : 1)),
            child: Material(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(AleraTokens.space16),
                  child: WorkflowRunControlPanel(
                    controls: WorkflowRunControls.fromJson(
                      workflowControlsFixture(executionStatus: 'running'),
                    ),
                    onControl: (_) {},
                    onReview: (_) {},
                    onRefresh: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
  });
}
