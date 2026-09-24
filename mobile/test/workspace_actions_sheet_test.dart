import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/linked_issues/application/linked_issues_controller.dart';
import 'package:alera_mobile/src/features/linked_issues/domain/mobile_linked_issue.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_host.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_section_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_hosts_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('workspace actions follow the desktop section grouping', (
    tester,
  ) async {
    await _openSheet(
      tester,
      workspace: _workspace('leaf'),
      data: _data(workspaces: <WorkspaceSummary>[_workspace('leaf')]),
    );

    expect(
      _sheetLabels(tester),
      containsAllInOrder(<String>[
        'Rename',
        'Pin Workspace',
        'Set Parent Workspace',
        'Section',
        'Manage Tags',
        'Link Issue',
        'Open',
        'Copy Path',
        'Sleep',
        'Archive',
        'Remove',
      ]),
    );
    expect(find.text('Open in Browser'), findsNothing);
    expect(find.text('Pin Workspace Tree'), findsNothing);
    expect(find.text('Apply to Tree'), findsNothing);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('In Browser'), findsOneWidget);

    await tester.tap(find.text('Section'));
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('New Section'), findsOneWidget);
  });

  testWidgets('tree workspaces nest pin, parent, section, and issue families', (
    tester,
  ) async {
    final ancestor = _workspace('root');
    final parent = _workspace(
      'parent',
      sectionId: 'work',
      parentWorkspaceId: ancestor.id,
    );
    final child = _workspace('child', parentWorkspaceId: parent.id);
    await _openSheet(
      tester,
      workspace: parent,
      data: _data(workspaces: <WorkspaceSummary>[ancestor, parent, child]),
      linked: const MobileLinkedIssue(
        workspaceId: 'parent',
        url: 'https://github.com/leynier/alera/issues/1',
      ),
    );

    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Parent'), findsOneWidget);
    expect(find.text('Section'), findsOneWidget);
    expect(find.text('Manage Tags'), findsOneWidget);
    expect(find.text('Issue'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Link Issue'), findsNothing);

    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();
    expect(find.text('Pin Workspace'), findsOneWidget);
    expect(find.text('Pin Workspace Tree'), findsOneWidget);

    await tester.tap(find.text('Parent'));
    await tester.pumpAndSettle();
    expect(find.text('Set Parent Workspace'), findsOneWidget);
    expect(find.text('Clear Parent Workspace'), findsOneWidget);

    await tester.ensureVisible(find.text('Section'));
    await tester.tap(find.text('Section'));
    await tester.pumpAndSettle();
    expect(find.text('Apply to Tree'), findsOneWidget);
    expect(find.text('Clear Section'), findsOneWidget);

    await tester.ensureVisible(find.text('Issue'));
    await tester.tap(find.text('Issue'));
    await tester.pumpAndSettle();
    expect(find.text('Open Issue in Browser'), findsOneWidget);
    expect(find.text('Change Linked Issue'), findsOneWidget);
    expect(find.text('Unlink Issue'), findsOneWidget);
  });

  testWidgets('10 or more sections flatten to Set Section on a leaf', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 20);
    await _openSheet(
      tester,
      workspace: _workspace('leaf'),
      data: _data(
        workspaces: <WorkspaceSummary>[_workspace('leaf')],
        sections: <WorkspaceSectionSummary>[
          for (var i = 0; i < 10; i++)
            WorkspaceSectionSummary(
              id: 's$i',
              name: 'Group $i',
              createdAt: now,
              updatedAt: now,
            ),
        ],
      ),
    );

    expect(find.text('Set Section'), findsOneWidget);
    expect(find.text('Section'), findsNothing);
    expect(find.text('New Section'), findsNothing);
  });

  testWidgets('the header names the host of a remote workspace only', (
    tester,
  ) async {
    final remote = _workspace('remote', hostId: 'ssh-tux');
    await _openSheet(
      tester,
      workspace: remote,
      data: _data(workspaces: <WorkspaceSummary>[remote]),
      hosts: _remoteHosts,
    );
    expect(find.byKey(const Key('workspace-actions-host')), findsOneWidget);
    expect(find.text('Rack (Linux)'), findsOneWidget);

    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    final local = _workspace('leaf');
    await _openSheet(
      tester,
      workspace: local,
      data: _data(workspaces: <WorkspaceSummary>[local]),
      hosts: _remoteHosts,
    );
    expect(find.byKey(const Key('workspace-actions-host')), findsNothing);
  });

  testWidgets('an older runtime shows no host in the header', (tester) async {
    final remote = _workspace('remote', hostId: 'ssh-tux');
    await _openSheet(
      tester,
      workspace: remote,
      data: _data(workspaces: <WorkspaceSummary>[remote]),
    );
    expect(find.byKey(const Key('workspace-actions-host')), findsNothing);
  });
}

const _remoteHosts = MobileWorkspaceHostDirectory(
  supported: true,
  byId: <String, MobileWorkspaceHost>{
    'ssh-tux': MobileWorkspaceHost(
      id: 'ssh-tux',
      alias: 'Rack',
      platform: 'linux',
    ),
  },
);

List<String> _sheetLabels(WidgetTester tester) {
  return tester
      .widgetList<Text>(
        find.descendant(of: find.byType(ListView), matching: find.byType(Text)),
      )
      .map((text) => text.data)
      .whereType<String>()
      .toList(growable: false);
}

Future<void> _openSheet(
  WidgetTester tester, {
  required WorkspaceSummary workspace,
  required WorkspaceListData data,
  MobileLinkedIssue? linked,
  MobileWorkspaceHostDirectory hosts = const MobileWorkspaceHostDirectory(),
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkedIssuesControllerProvider.overrideWith2(
          (_) => _LinkedIssues(_linkedSnapshot(linked)),
        ),
        workspaceHostsControllerProvider.overrideWith2((_) => _Hosts(hosts)),
      ],
      child: MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final issues = ref.watch(
                linkedIssuesControllerProvider('host-1'),
              );
              ref.watch(workspaceHostsControllerProvider('host-1'));
              return Column(
                children: <Widget>[
                  Text(issues.hasValue ? 'Ready' : 'Loading'),
                  TextButton(
                    onPressed: () => showWorkspaceActionsSheet(
                      context,
                      ref,
                      hostId: 'host-1',
                      workspace: workspace,
                      data: data,
                    ),
                    child: const Text('Open Sheet'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Ready'), findsOneWidget);
  await tester.tap(find.text('Open Sheet'));
  await tester.pumpAndSettle();
}

MobileLinkedIssueSnapshot _linkedSnapshot(MobileLinkedIssue? linked) {
  final byWorkspace = <String, MobileLinkedIssue>{};
  if (linked != null) {
    byWorkspace[linked.workspaceId] = linked;
  }
  return MobileLinkedIssueSnapshot(supported: true, byWorkspace: byWorkspace);
}

WorkspaceListData _data({
  required List<WorkspaceSummary> workspaces,
  List<WorkspaceSectionSummary>? sections,
}) {
  final now = DateTime.utc(2026, 9, 20);
  return WorkspaceListData(
    sections:
        sections ??
        <WorkspaceSectionSummary>[
          WorkspaceSectionSummary(
            id: 'work',
            name: 'Work',
            createdAt: now,
            updatedAt: now,
          ),
        ],
    supportsSections: true,
    workspaces: workspaces,
    projects: const <ProjectSummary>[
      ProjectSummary(id: 'project-1', name: 'Alera', repoPath: '/repo'),
    ],
    supportsMutations: true,
    supportsArchive: true,
    tags: const <WorkspaceTagSummary>[],
    activity: const <String, DateTime>{},
    confirmWorkspaceRemoval: true,
    agentPresence: const <AgentPresenceSummary>[],
  );
}

WorkspaceSummary _workspace(
  String id, {
  String hostId = 'local',
  String? sectionId,
  String? parentWorkspaceId,
}) {
  return WorkspaceSummary(
    id: id,
    hostId: hostId,
    projectId: 'project-1',
    name: id,
    path: '/repo/$id',
    sectionId: sectionId,
    parentWorkspaceId: parentWorkspaceId,
  );
}

class _LinkedIssues extends LinkedIssuesController {
  _LinkedIssues(this.snapshot);

  final MobileLinkedIssueSnapshot snapshot;

  @override
  Future<MobileLinkedIssueSnapshot> build(String hostId) async => snapshot;
}

class _Hosts extends WorkspaceHostsController {
  _Hosts(this.directory);

  final MobileWorkspaceHostDirectory directory;

  @override
  Future<MobileWorkspaceHostDirectory> build(String hostId) async => directory;
}
