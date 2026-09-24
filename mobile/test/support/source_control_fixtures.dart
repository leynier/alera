import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_terminal_client.dart';

MobileGitChange unstagedChange() => const MobileGitChange(
  path: 'lib/main.dart',
  area: 'unstaged',
  status: 'modified',
  canStage: true,
  canDiscard: true,
);

MobileGitChange stagedChange() => const MobileGitChange(
  path: 'lib/main.dart',
  area: 'staged',
  status: 'modified',
  canUnstage: true,
);

MobileGitStatusSnapshot writableSnapshot({
  bool writable = true,
  List<MobileGitChange> entries = const <MobileGitChange>[],
  MobileSourceControlActions actions = const MobileSourceControlActions(
    stageAll: true,
    fetch: true,
  ),
  String primaryAction = 'fetch',
  String? headMessage,
  List<MobileGitStash> stashes = const <MobileGitStash>[],
}) => MobileGitStatusSnapshot(
  isRepository: true,
  branch: 'main',
  writable: writable,
  entries: entries,
  actions: actions,
  primaryAction: primaryAction,
  repository: MobileGitRepositoryState(
    upstream: 'origin/main',
    headMessage: headMessage,
  ),
  stashes: stashes,
);

FakeTerminalClient sourceControlClient(MobileGitStatusSnapshot snapshot) =>
    FakeTerminalClient()
      ..sourceControlSupported = true
      ..sourceControlWritesSupported = true
      ..gitStatusSnapshot = snapshot;

Future<void> openSourceControlMenu(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Source Control Actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, label));
  await tester.pumpAndSettle();
}

Future<void> pumpSourceControlPanel(
  WidgetTester tester,
  FakeTerminalClient client,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
      child: MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: const Scaffold(
          body: SourceControlPanel(
            hostId: 'host-1',
            workspaceId: 'workspace-1',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
