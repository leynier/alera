import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_status_notification_activation_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workspace_focus/application/workspace_focus_request_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('workspaceFocusRequestId', () {
    test('reads the workspace id of a focus request only', () {
      expect(
        workspaceFocusRequestId(
          const RuntimeHostEvent('workspaceFocusRequested', <String, Object?>{
            'workspaceId': ' workspace-2 ',
            'projectId': 'project-1',
          }),
        ),
        'workspace-2',
      );
      expect(
        workspaceFocusRequestId(
          const RuntimeHostEvent('workspacesChanged', <String, Object?>{
            'workspaceId': 'workspace-2',
          }),
        ),
        isNull,
      );
      expect(
        workspaceFocusRequestId(
          const RuntimeHostEvent('workspaceFocusRequested', <String, Object?>{
            'workspaceId': '  ',
          }),
        ),
        isNull,
      );
    });

    test('is a runtime event the app listens to and announces in hello', () {
      expect(
        runtimeHostEventNames,
        contains(aleraWorkspaceFocusRequestedEvent),
      );
      expect(aleraWorkspaceFocusHelloFlag, 'workspaceFocusV1');
    });
  });

  group('WorkspaceFocusRequestHandler', () {
    test(
      'shows the window, leaves overlays, and selects the workspace',
      () async {
        final workbench = _FakeWorkbench(_state(workspaceIds: ['w-1', 'w-2']));
        final window = _FakeWindow();

        final selected = await _handler(window, workbench).focus('w-2');

        expect(selected, isTrue);
        expect(window.calls, 1);
        expect(workbench.overlayCloses, 1);
        expect(workbench.selected, <String>['project-1/w-2']);
      },
    );

    test('waits for a workspace that loads after the request', () async {
      final workbench = _FakeWorkbench(_state(workspaceIds: ['w-1']));
      final window = _FakeWindow();

      final pending = _handler(window, workbench).focus('w-new');
      await Future.pause(.zero);
      expect(window.calls, 0);
      workbench.emit(_state(workspaceIds: ['w-1', 'w-new']));

      expect(await pending, isTrue);
      expect(workbench.selected, <String>['project-1/w-new']);
    });

    test('waits for bootstrap before resolving the workspace', () async {
      final workbench = _FakeWorkbench(
        _state(workspaceIds: ['w-1'], bootstrapped: false),
      );

      final pending = _handler(_FakeWindow(), workbench).focus('w-1');
      await Future.pause(.zero);
      expect(workbench.selected, isEmpty);
      workbench.emit(_state(workspaceIds: ['w-1']));

      expect(await pending, isTrue);
      expect(workbench.selected, <String>['project-1/w-1']);
    });

    test('gives up quietly when the workspace never appears', () async {
      final workbench = _FakeWorkbench(_state(workspaceIds: ['w-1']));
      final window = _FakeWindow();

      final selected = await _handler(
        window,
        workbench,
        wait: const Duration(milliseconds: 10),
      ).focus('missing');

      expect(selected, isFalse);
      expect(window.calls, 0, reason: 'nothing to show, so no focus steal');
      expect(workbench.overlayCloses, 0);
      expect(workbench.selected, isEmpty);
    });

    test('a newer request supersedes one still waiting', () async {
      final workbench = _FakeWorkbench(_state(workspaceIds: ['w-1']));
      final handler = _handler(_FakeWindow(), workbench);

      final older = handler.focus('w-late');
      final newer = handler.focus('w-1');
      expect(await newer, isTrue);
      workbench.emit(_state(workspaceIds: ['w-1', 'w-late']));

      expect(await older, isFalse);
      expect(workbench.selected, <String>['project-1/w-1']);
    });
  });
}

WorkspaceFocusRequestHandler _handler(
  _FakeWindow window,
  _FakeWorkbench workbench, {
  Duration wait = const Duration(seconds: 5),
}) => WorkspaceFocusRequestHandler(
  windowActivator: window,
  workbench: workbench,
  workspaceWait: wait,
);

WorkbenchState _state({
  required List<String> workspaceIds,
  bool bootstrapped = true,
}) {
  final now = DateTime.utc(2026, 10, 6);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo',
    createdAt: now,
    updatedAt: now,
  );
  return WorkbenchState(
    bootstrapped: bootstrapped,
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{
      project.id: <Workspace>[
        for (final id in workspaceIds)
          Workspace(
            id: id,
            projectId: project.id,
            name: id,
            path: '/repo/$id',
            createdAt: now,
            updatedAt: now,
            kind: .linked,
            status: .active,
          ),
      ],
    },
  );
}

class _FakeWindow implements AgentNotificationWindowActivator {
  int calls = 0;

  @override
  Future<void> showAndFocus() async => calls++;
}

class _FakeWorkbench(var WorkbenchState _current)
    implements WorkspaceFocusWorkbench {
  final StreamController<WorkbenchState> _changes =
      StreamController<WorkbenchState>.broadcast(sync: true);
  final List<String> selected = <String>[];
  int overlayCloses = 0;

  void emit(WorkbenchState next) {
    _current = next;
    _changes.add(next);
  }

  @override
  WorkbenchState get state => _current;

  @override
  Stream<WorkbenchState> get stateChanges => _changes.stream;

  @override
  void closeOverlays() => overlayCloses++;

  @override
  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) async {
    selected.add('${project.id}/${workspace.id}');
    _current = _current.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: workspace.id,
    );
  }
}
