import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/activity_section.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:alera_mobile/src/features/runs/domain/run_tab_identity.dart';
import 'package:alera_mobile/src/features/runs/presentation/activity_screen.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_detail_screen.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_runs_client.dart';
import 'support/fake_terminal_client.dart';

/// SQLite's `datetime('now')` shape, which the runtime stamps rows with.
String _sqlite(DateTime value) {
  String two(int part) => part.toString().padLeft(2, '0');
  final utc = value.toUtc();
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
}

Widget _app(FakeRunsClient client, Widget child) => ProviderScope(
  overrides: [
    mobileRunsClientProvider('host').overrideWith((ref) async => client),
  ],
  child: MaterialApp(home: child),
);

void main() {
  group('runtime data links', () {
    test('board rows, task times and resource counts parse', () {
      final run = RunSummary.fromJson(<String, Object?>{
        ...runSummaryJson(),
        'pendingGates': <Object?>[
          <String, Object?>{'id': 'gate-plan', 'kind': 'plan'},
          <String, Object?>{
            'id': 'gate-decision',
            'kind': 'decision',
            'taskId': 'task-1',
          },
          <String, Object?>{'kind': 'stage'},
        ],
      });
      expect(run.pendingGates.map((gate) => gate.id), <String>[
        'gate-plan',
        'gate-decision',
      ]);
      expect(run.pendingGates.first.kind, RunGateKind.plan);
      expect(run.pendingGates.last.taskId, 'task-1');
      expect(RunSummary.fromJson(runSummaryJson()).pendingGates, isEmpty);

      final detail = RunDetail.fromJson(<String, Object?>{
        ...runSnapshotJson(
          tasks: <Map<String, Object?>>[
            <String, Object?>{
              ...runTaskJson(),
              'startedAt': '2026-10-11 09:10:00',
              'completedAt': null,
              'updatedAt': '2026-10-11 09:50:00',
            },
          ],
        ),
        'resourceCount': 3,
      });
      expect(detail.resourceCount, 3);
      final task = detail.tasks.single;
      expect(task.startedAt, DateTime.utc(2026, 10, 11, 9, 10));
      expect(task.updatedAt, DateTime.utc(2026, 10, 11, 9, 50));
      expect(task.completedAt, isNull);
      expect(RunDetail.fromJson(runSnapshotJson()).resourceCount, isNull);

      expect(
        RunTabIdentity.fromPayload(const <String, Object?>{
          'runId': 'run-1',
          'runTaskId': 'task-1',
        })?.taskId,
        'task-1',
      );
      expect(
        RunTabIdentity.fromPayload(const <String, Object?>{'runId': ''}),
        isNull,
      );
    });

    testWidgets('a run that names its due gate opens on that gate', (
      tester,
    ) async {
      final client = FakeRunsClient();
      addTearDown(client.dispose);
      client.runs = <Map<String, Object?>>[
        <String, Object?>{
          ...runSummaryJson(
            id: 'run-1',
            objective: 'Fix flaky login test',
            status: 'paused',
            bucket: 'attention',
            pendingGateCount: 1,
            pendingGateKinds: const <String>['stage'],
          ),
          'pendingGates': <Object?>[
            <String, Object?>{'id': 'gate-named', 'kind': 'stage'},
          ],
        },
      ];
      await tester.pumpWidget(
        _app(
          client,
          const ActivityScreen(
            hostId: 'host',
            initialSection: ActivitySection.runs,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fix flaky login test'));
      await tester.pumpAndSettle();
      final screen = tester.widget<RunDetailScreen>(
        find.byType(RunDetailScreen),
      );
      expect(screen.initialGateId, 'gate-named');
      expect(client.callsOf('runs.gates'), isEmpty);
    });

    testWidgets('task rows show their age and Clean Up its retained count', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = FakeRunsClient();
      addTearDown(client.dispose);
      client.snapshots['run-1'] = <String, Object?>{
        ...runSnapshotJson(
          run: runSummaryJson(
            status: 'completed',
            bucket: 'history',
            completedAt: '2026-10-11T10:00:00Z',
          ),
          tasks: <Map<String, Object?>>[
            <String, Object?>{
              ...runTaskJson(status: 'completed', attemptState: 'integrated'),
              'updatedAt': _sqlite(
                DateTime.now().subtract(const Duration(hours: 2, minutes: 5)),
              ),
            },
          ],
        ),
        'resourceCount': 2,
      };
      await tester.pumpWidget(
        _app(client, const RunDetailScreen(hostId: 'host', runId: 'run-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2h ago'), findsOneWidget);

      await tester.tap(find.byTooltip('More Actions'));
      await tester.pumpAndSettle();
      final badge = find.byKey(const ValueKey<String>('run-resource-count'));
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('View Run on a run terminal opens the run', (tester) async {
      final terminal = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          const WorkspaceTabSummary(
            id: 'plain',
            workspaceId: 'workspace-1',
            kind: 'terminal',
            title: 'Plain Shell',
            payload: <String, Object?>{'terminalSessionId': 'session-plain'},
          ),
          const WorkspaceTabSummary(
            id: 'worker',
            workspaceId: 'workspace-1',
            kind: 'terminal',
            title: 'Run Worker',
            payload: <String, Object?>{
              'terminalSessionId': 'session-worker',
              'runId': 'run-1',
              'runTaskId': 'task-1',
            },
          ),
        ];
      addTearDown(terminal.dispose);
      final runs = FakeRunsClient();
      addTearDown(runs.dispose);
      runs.snapshots['run-1'] = runSnapshotJson();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            terminalClientProvider('host')
                .overrideWith((ref) async => terminal),
            workspaceClientProvider('host')
                .overrideWith((ref) async => terminal),
            mobileRunsClientProvider('host').overrideWith((ref) async => runs),
          ],
          child: const MaterialApp(
            home: WorkspaceTabsScreen(
              hostId: 'host',
              workspace: WorkspaceSummary(
                id: 'workspace-1',
                projectId: 'project',
                name: 'Workspace',
                path: '/repo',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Plain Shell'));
      await tester.pumpAndSettle();
      expect(find.text('View Run'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Run Worker'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Run'));
      await tester.pumpAndSettle();
      final screen = tester.widget<RunDetailScreen>(
        find.byType(RunDetailScreen),
      );
      expect(screen.runId, 'run-1');
      expect(runs.callsOf('runs.snapshot'), isNotEmpty);
    });
  });
}
