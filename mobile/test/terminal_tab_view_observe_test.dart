import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_accessory_layout_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_clipboard_settings_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_compose_bar.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_tab_view.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_automation_client.dart';
import 'support/fake_terminal_client.dart';
import 'support/memory_accessory_layout_repository.dart';

class _NoClipboard extends TerminalClipboardSettingsController {
  @override
  Future<bool> build() async => false;
}

Future<void> _pump(
  WidgetTester tester,
  FakeTerminalClient client,
  FakeAutomationClient automations, {
  required bool observe,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalClientProvider('host-1').overrideWith((ref) async => client),
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
        mobileAutomationClientProvider('host-1')
            .overrideWith((ref) async => automations),
        accessoryLayoutRepositoryProvider.overrideWithValue(
          MemoryAccessoryLayoutRepository(),
        ),
        terminalClipboardSettingsControllerProvider.overrideWith(
          _NoClipboard.new,
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: TerminalTabView(
            hostId: 'host-1',
            workspaceId: 'workspace-1',
            tabId: 'tab-1',
            observe: observe,
            automationRunId: 'run-1',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an observed automation tab attaches read-only with no input', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Agent')];
    final automations = FakeAutomationClient();
    addTearDown(automations.dispose);
    await _pump(tester, client, automations, observe: true);

    expect(client.calls, contains('observe tab-1'));
    expect(client.calls, isNot(contains('attach tab-1')));
    expect(find.byType(TerminalComposeBar), findsNothing);
    expect(
      find.text('An automation run is working here. Read only.'),
      findsOneWidget,
    );
    expect(client.calls.where((call) => call.startsWith('resize')), isEmpty);
    expect(client.writes, isEmpty);

    await tester.tap(find.text('Take Over'));
    await tester.pumpAndSettle();
    expect(automations.callsOf('automation.takeOver').single.payload, {
      'runId': 'run-1',
    });
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('ordinary tabs keep the normal attach', (tester) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Shell')];
    final automations = FakeAutomationClient();
    addTearDown(automations.dispose);
    await _pump(tester, client, automations, observe: false);
    expect(client.calls, contains('attach tab-1'));
    expect(find.byType(TerminalComposeBar), findsOneWidget);
  });
}
