import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/design_system/icons/alera_codicons.dart';
import 'package:alera_mobile/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_host.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_workspace_host_requests.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_listing_tree.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_row_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _local = WorkspaceSummary(
  id: 'workspace-local',
  projectId: 'project-1',
  name: 'Local',
  path: '/repo',
);
const _remote = WorkspaceSummary(
  id: 'workspace-remote',
  hostId: 'ssh-mac',
  projectId: 'project-1',
  name: 'Remote',
  path: '/Users/dev/repo',
);

void main() {
  test('normalizes the platform spellings the runtime may report', () {
    expect(HostOs.parse('macos'), HostOs.macos);
    expect(HostOs.parse(' Darwin '), HostOs.macos);
    expect(HostOs.parse('mac'), HostOs.macos);
    expect(HostOs.parse('windows'), HostOs.windows);
    expect(HostOs.parse('win32'), HostOs.windows);
    expect(HostOs.parse('Windows_NT'), HostOs.windows);
    expect(HostOs.parse('linux'), HostOs.linux);
    expect(HostOs.parse('freebsd'), HostOs.unknown);
    expect(HostOs.parse(null), HostOs.unknown);
  });

  test('a directory marks remote workspaces only when supported', () {
    const directory = MobileWorkspaceHostDirectory(
      supported: true,
      byId: <String, MobileWorkspaceHost>{
        'ssh-mac': MobileWorkspaceHost(
          id: 'ssh-mac',
          alias: 'Studio Mac',
          platform: 'darwin',
        ),
      },
    );
    expect(directory.hostOf(_local), isNull);
    expect(directory.hostOf(_remote)?.label, 'Studio Mac (macOS)');
    // A host the runtime stopped naming still marks the row as remote.
    final unnamed = directory.hostOf(
      const WorkspaceSummary(
        id: 'workspace-gone',
        hostId: 'ssh-gone',
        projectId: 'project-1',
        name: 'Gone',
        path: '/repo',
      ),
    );
    expect(unnamed?.label, 'ssh-gone');
    expect(unnamed?.os, HostOs.unknown);
    expect(const MobileWorkspaceHostDirectory().hostOf(_remote), isNull);
  });

  test('the runtime mixin lists hosts only with the capability', () async {
    final client = _FakeRequests(<String>{mobileRemoteWorkspacesCapability});
    expect(client.supportsRemoteWorkspaces, isTrue);
    final hosts = await client.listWorkspaceHosts();
    expect(client.requested, <String>['mobile.hosts.list']);
    expect(hosts.map((host) => host.id), <String>['ssh-mac', 'ssh-raw']);
    expect(hosts.first.alias, 'Studio Mac');
    expect(hosts.first.os, HostOs.macos);
    // A missing alias falls back to the id, a null platform to the generic OS.
    expect(hosts.last.alias, 'ssh-raw');
    expect(hosts.last.os, HostOs.unknown);

    final older = _FakeRequests(const <String>{});
    expect(older.supportsRemoteWorkspaces, isFalse);
    expect(await older.listWorkspaceHosts(), isEmpty);
    expect(older.requested, isEmpty);
  });

  testWidgets('a remote row shows the host OS icon labelled with the alias', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpRow(
      tester,
      _remote,
      host: const MobileWorkspaceHost(
        id: 'ssh-mac',
        alias: 'Studio Mac',
        platform: 'macos',
      ),
    );
    expect(find.byKey(const Key('workspace-tray-host')), findsOneWidget);
    expect(find.byIcon(LucideIcons.apple), findsOneWidget);
    expect(find.byTooltip('Studio Mac (macOS)'), findsOneWidget);
    // The row merges its children into one node, so the alias is part of
    // what a screen reader says for the row.
    expect(
      tester.getSemantics(find.byKey(const Key('workspace-tray-host'))).label,
      contains('Host Studio Mac (macOS)'),
    );

    await tester.longPress(find.byKey(const Key('workspace-tray-host')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Studio Mac (macOS)'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('each platform draws its own glyph', (tester) async {
    await _pumpRow(
      tester,
      _remote,
      host: const MobileWorkspaceHost(
        id: 'ssh-tux',
        alias: 'Rack',
        platform: 'linux',
      ),
    );
    expect(find.byIcon(AleraCodicons.terminalLinux), findsOneWidget);

    await _pumpRow(
      tester,
      _remote,
      host: const MobileWorkspaceHost(
        id: 'ssh-win',
        alias: 'Build Box',
        platform: 'win32',
      ),
    );
    expect(find.byTooltip('Build Box (Windows)'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('workspace-tray-host')),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );

    await _pumpRow(
      tester,
      _remote,
      host: const MobileWorkspaceHost(id: 'ssh-bsd', alias: 'Attic'),
    );
    expect(find.byIcon(AleraIcons.host), findsOneWidget);
    expect(find.byTooltip('Attic'), findsOneWidget);
  });

  testWidgets('a local row shows no host icon', (tester) async {
    await _pumpRow(tester, _local);
    expect(find.byKey(const Key('workspace-tray-host')), findsNothing);
    expect(find.byType(AleraHostOsIcon), findsNothing);
  });
}

Future<void> _pumpRow(
  WidgetTester tester,
  WorkspaceSummary workspace, {
  MobileWorkspaceHost? host,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAleraMobileDarkTheme(),
      home: Scaffold(
        body: MobileWorkspaceListRow(
          row: MobileWorkspaceEntryRow(
            entry: WorkspaceTreeEntry(
              workspace: workspace,
              depth: 0,
              visibleChildCount: 0,
              childrenCollapsed: false,
            ),
          ),
          onTap: () {},
          onLongPress: () {},
          onMore: () {},
          onToggleChildren: () {},
          terminalTabCount: 0,
          agentsExpanded: false,
          onToggleAgents: () {},
          onAgentTap: (_) {},
          onCloseAgent: (_) {},
          host: host,
        ),
      ),
    ),
  );
}

class _FakeRequests with MobileRuntimeWorkspaceHostRequests {
  _FakeRequests(this.runtimeCapabilities);

  @override
  final Set<String> runtimeCapabilities;
  final List<String> requested = <String>[];

  @override
  Future<List<Object?>> requestList(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    requested.add(type);
    return <Object?>[
      <String, Object?>{
        'id': 'ssh-mac',
        'alias': 'Studio Mac',
        'platform': 'darwin',
      },
      <String, Object?>{'id': 'ssh-raw', 'platform': null},
    ];
  }
}
