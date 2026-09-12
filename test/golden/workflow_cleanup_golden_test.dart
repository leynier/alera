import 'package:alchemist/alchemist.dart';
import 'package:alera/src/features/orchestration/application/workflow_cleanup_session.dart';
import 'package:alera/src/features/orchestration/domain/workflow_cleanup_snapshot.dart';
import 'package:alera/src/features/orchestration/infra/workflow_cleanup_repository.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_cleanup_review_panel.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_cleanup_selection_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workflow_cleanup_fixture.dart';
import '../support/workflow_cleanup_catalog_fixture.dart';
import 'alera_golden_harness.dart';

void main() {
  runAleraGoldenTests(() {
    for (final compact in [false, true]) {
      for (final state in ['selection', 'preview', 'attention']) {
        goldenTest(
          'Cleanup $state ${compact ? "compact" : "desktop"}',
          fileName:
              'workflow_cleanup_${state}_${compact ? "compact" : "desktop"}',
          constraints: BoxConstraints.tightFor(
            width: compact ? 420 : 760,
            height: compact ? 1500 : 900,
          ),
          builder: () {
            final session = WorkflowCleanupSession(_UnusedRepository(), 'run');
            addTearDown(session.dispose);
            session.resources = WorkflowCleanupPage.fromJson(
              cleanupResourcesFixture(),
              WorkflowCleanupResource.fromJson,
            ).items;
            session.history = WorkflowCleanupPage.fromJson(
              cleanupHistoryFixture(),
              WorkflowCleanupSummary.fromJson,
            ).items;
            session.loading = false;
            session.select('workspace', true);
            return MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(compact ? 2 : 1),
              ),
              child: Material(
                child: state == 'selection'
                    ? WorkflowCleanupSelectionPanel(
                        session: session,
                        allowPrepare: true,
                        onBack: () {},
                        onOpen: (_) {},
                        onWorkspace: (_) {},
                      )
                    : WorkflowCleanupReviewPanel(
                        status: WorkflowCleanupStatus.fromJson(
                          cleanupStatusFixture(state),
                        ),
                        now: DateTime.utc(2026),
                        onBack: () {},
                        onRefresh: () {},
                        onApply: (_) {},
                        onOpenWorkspace: (_) {},
                      ),
              ),
            );
          },
        );
      }
    }
  });
}

class _UnusedRepository implements WorkflowCleanupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
