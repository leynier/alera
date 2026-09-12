import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  testWidgets('first load blocks with a spinner', (tester) async {
    final client = _client()..gitStatusGate = Completer<void>();
    addTearDown(client.dispose);

    await _pumpPanel(tester, client);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('main.dart'), findsNothing);

    client.gitStatusGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('main.dart'), findsOneWidget);
  });

  testWidgets('reload keeps the previous snapshot on screen', (tester) async {
    final client = _client();
    addTearDown(client.dispose);
    await _pumpPanel(tester, client);
    expect(find.text('main.dart'), findsOneWidget);

    client.gitStatusGate = Completer<void>();
    final reload = _controller(tester).reload();
    await tester.pump();

    expect(find.text('main.dart'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    client
      ..gitStatusSnapshot = _snapshot('lib/app.dart')
      ..gitStatusGate!.complete();
    await reload;
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('app.dart'), findsOneWidget);
    expect(find.text('main.dart'), findsNothing);
  });

  testWidgets('failed reload keeps the list and reports the error', (
    tester,
  ) async {
    final client = _client();
    addTearDown(client.dispose);
    await _pumpPanel(tester, client);

    client.gitStatusError = StateError('socket closed');
    await _controller(tester).reload();
    await tester.pumpAndSettle();

    expect(find.text('main.dart'), findsOneWidget);
    expect(find.textContaining('Could not refresh source control'), findsOne);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('client rebuild does not blank the panel', (tester) async {
    final client = _client();
    addTearDown(client.dispose);
    await _pumpPanel(tester, client);

    client.gitStatusGate = Completer<void>();
    ProviderScope.containerOf(tester.element(find.byType(SourceControlPanel)))
        .invalidate(workspaceClientProvider('host-1'));
    await tester.pump();
    await tester.pump();

    expect(find.text('main.dart'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    client.gitStatusGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsOneWidget);
  });
}

FakeTerminalClient _client() => FakeTerminalClient()
  ..sourceControlSupported = true
  ..gitStatusSnapshot = _snapshot('lib/main.dart');

MobileGitStatusSnapshot _snapshot(String path) => MobileGitStatusSnapshot(
  isRepository: true,
  branch: 'main',
  entries: <MobileGitChange>[
    MobileGitChange(path: path, area: 'unstaged', status: 'modified'),
  ],
);

SourceControlController _controller(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(SourceControlPanel)),
    ).read(sourceControlControllerProvider('host-1', 'workspace-1').notifier);

Future<void> _pumpPanel(WidgetTester tester, FakeTerminalClient client) async {
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
  await tester.pump();
}
