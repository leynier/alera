import 'package:alera/src/features/runs/domain/recipe_catalog_entry.dart';
import 'package:alera/src/features/runs/domain/run_cleanup.dart';
import 'package:alera/src/features/runs/domain/run_create_request.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_plan.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:alera/src/features/runs/domain/run_task_inspection.dart';
import 'package:alera/src/features/runs/domain/run_timeline.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/runs_fixtures.dart';

void main() {
  test('every run error code has a sentence-case message', () {
    const codes = <String>[
      'gate_stale',
      'gate_not_due',
      'gate_not_pending',
      'gate_not_found',
      'gate_invalid_resolution',
      'gate_not_resolvable',
      'run_not_found',
      'run_sequence_stale',
      'run_finished',
      'run_gate_pending',
      'run_reason_required',
      'run_has_active_work',
      'run_integration_pending',
      'run_nothing_to_retry',
      'run_retry_unavailable',
      'run_workspace_busy',
      'run_not_isolated',
      'run_not_paused',
      'run_not_running',
      'run_request_conflict',
    ];
    for (final code in codes) {
      final message = runErrorMessage(
        TerminalHostConflictException(code: code, message: 'raw $code'),
      );
      expect(message, isNot('raw $code'), reason: code);
      expect(message, endsWith('.'), reason: code);
    }
    expect(
      runErrorMessage(
        const TerminalHostConflictException(code: 'future', message: 'raw'),
      ),
      'raw',
    );
    expect(
      runErrorMessage(const RunsUpdateRequired(recipes: true)),
      'Update the runtime to manage recipes.',
    );
    expect(
      runErrorMessage(const TerminalHostConnectionClosedException()),
      'The Alera runtime is not reachable.',
    );
    expect(runErrorMessage(StateError('boom')), 'Boom');
    expect(
      runErrorMessage(Exception('Bad state: run store locked')),
      'Run store locked',
    );
    for (final code in <String>[
      'gate_stale',
      'run_sequence_stale',
      'gate_not_pending',
      'gate_not_due',
    ]) {
      expect(
        isRunStaleError(TerminalHostConflictException(code: code, message: '')),
        isTrue,
        reason: code,
      );
    }
    expect(
      isRunStaleError(
        const TerminalHostConflictException(code: 'run_finished', message: ''),
      ),
      isFalse,
    );
    expect(isRunStaleError(StateError('boom')), isFalse);
  });

  test('recipe origins and roles read from catalog records', () {
    expect(recipeOriginLabel(const {'origin': 'personal'}), 'Personal');
    expect(recipeOriginLabel(const {'origin': 'project'}), 'Project');
    expect(recipeOriginLabel(const {}), 'Unknown Origin');
    expect(
      RecipeCatalogEntry.fromJson(const {
        'source': {'origin': 'personal', 'id': 'mine'},
        'name': 'Mine',
      }).label,
      'Mine (Personal)',
    );
  });

  test('a plan view decodes stages, tasks and its recipe', () {
    final plan = RunPlanView.fromJson(const <String, Object?>{
      'runId': 'run-1',
      'revision': 2,
      'recipe': {'name': 'Feature Delivery'},
      'stages': [
        {'id': 'foundation', 'title': 'Foundation', 'gate': true},
        {'id': 'product'},
      ],
      'tasks': [
        {
          'id': 'scaffold',
          'title': 'Scaffold the provider',
          'stageId': 'foundation',
          'dependsOn': ['config'],
        },
      ],
    });
    expect(plan.recipeName, 'Feature Delivery');
    expect(plan.stages.map((stage) => stage.label), ['Foundation', 'product']);
    expect(plan.tasks.single.dependsOn, ['config']);
  });

  test('a gate detail decodes its plan and evidence', () {
    final detail = RunGateDetail.fromJson(<String, Object?>{
      'gate': runGateJson(),
      'tasks': const [
        {
          'taskId': 'task-1',
          'title': 'Scaffold the provider',
          'status': 'completed',
          'conflictPaths': ['lib/a.dart'],
        },
      ],
    });
    expect(detail.gate.actionable, isTrue);
    expect(detail.plan, isNull);
    expect(detail.tasks.single.conflictPaths, ['lib/a.dart']);
  });

  test('create results and sources decode', () {
    final created = RunCreateResult.fromJson(const <String, Object?>{
      'run': {'runId': 'run-1', 'status': 'planning'},
      'coordinator': {'error': 'codex: command not found'},
    });
    expect(created.coordinatorError, 'codex: command not found');
    expect(
      const RunCreateResult(
        run: RunCreated(runId: 'run-1', status: 'planning'),
      ).coordinatorError,
      isNull,
    );
    final source = RunSource.fromJson(const <String, Object?>{
      'sha': 'a1b2c3d',
      'hasUncommittedChanges': true,
    });
    expect(source.sha, 'a1b2c3d');
    expect(source.hasUncommittedChanges, isTrue);
  });

  test('cleanup resources and pages check their run', () {
    final resource = RunCleanupResource.fromJson(const {
      'identity': {
        'runId': 'run-1',
        'attempt': 1,
        'baseSha': 'a1b2c3d',
        'workspace': {
          'id': 'ws-1',
          'name': 'rename-core',
          'path': '/w/rename-core',
          'branch': 'alera/runs/run-1/rename-core',
        },
      },
      'phase': 'attention',
      'registered': true,
      'retired': false,
      'cleanupId': 'cleanup-1',
      'cleanupState': 'attention',
    });
    expect(resource.cleanupState, RunCleanupState.attention);
    expect(resource.canSelect, isFalse);

    final page = RunCleanupPage<Map>.fromJson(const <String, Object?>{
      'runId': 'run-1',
      'revision': 3,
      'items': [<String, Object?>{}],
    }, (item) => item);
    page.requireRun('run-1');
    expect(() => page.requireRun('run-2'), throwsFormatException);
  });

  test('snapshot, inspection and timeline value types decode', () {
    final cleanup = RunCleanupSummaryMapper.fromMap(const <String, Object?>{
      'id': 'cleanup-1',
      'state': 'attention',
    });
    expect(cleanup.abandoned, isFalse);

    final cursor = TaskHistoryCursorMapper.fromMap(const <String, Object?>{
      'occurredAt': '2026-09-30T14:02:00Z',
      'id': 'h-1',
      'revision': 7,
    });
    expect(cursor.revision, 7);

    final entry = RunTimelineEntryMapper.fromMap(const <String, Object?>{
      'id': 'e-1',
      'source': 'event',
      'kind': 'integrated',
      'createdAt': '2026-09-30T13:35:00Z',
      'payload': {'sha': '9f8e7d6'},
    });
    expect(entry.payloadValue('sha'), '9f8e7d6');
    expect(
      timelineEntry(
        id: 'e-2',
        kind: 'created',
        createdAt: '2026-09-30T13:00:00Z',
      ).payloadValue('sha'),
      isNull,
    );
  });
}
