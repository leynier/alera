import 'dart:async';

import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_accessory_layout_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_compose_bar.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_tab_view.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

import 'support/fake_terminal_client.dart';
import 'support/memory_accessory_layout_repository.dart';

void main() {
  testWidgets('The composer outlives a session reload with its text', (
    tester,
  ) async {
    // A reload used to replace the whole column, disposing the controller that
    // an in-flight attachment pick was waiting to write its path into.
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    addTearDown(client.dispose);
    final lifecycle = _ComposerLifecycleController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          terminalClientProvider('host-1').overrideWith((ref) async => client),
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
          appLifecycleControllerProvider.overrideWith(() => lifecycle),
          accessoryLayoutRepositoryProvider.overrideWithValue(
            MemoryAccessoryLayoutRepository(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TerminalTabView(
              hostId: 'host-1',
              workspaceId: 'workspace-1',
              tabId: 'tab-1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'echo hola');
    await tester.pump();
    expect(find.byType(TerminalView), findsOneWidget);

    final reattach = Completer<void>();
    client
      ..attachCompletion = reattach.future
      ..probeError = StateError('connection gone');
    lifecycle.setLifecycleState(.inactive);
    lifecycle.setLifecycleState(.resumed);
    for (var frame = 0; frame < 10 && client.attachments.length < 2; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(client.attachments, hasLength(2));
    expect(find.byType(TerminalView), findsNothing);
    expect(find.byType(TerminalComposeBar), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'echo hola',
    );

    reattach.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'echo hola',
    );
  });
}

class _ComposerLifecycleController extends AppLifecycleController {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;

  void setLifecycleState(AppLifecycleState next) {
    state = next;
  }
}
