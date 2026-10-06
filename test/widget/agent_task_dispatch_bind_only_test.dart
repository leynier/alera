import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/agent_task_dispatch/presentation/agent_task_dispatch_dialog.dart';
import 'package:alera/src/features/agent_task_dispatch/presentation/agent_task_dispatch_launcher.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoProfiles extends AgentProfiles {
  @override
  Future<List<AgentProfile>> build() async => const <AgentProfile>[];
}

Future<void> _openPicker(WidgetTester tester, {required bool bindOnly}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workbenchControllerProvider.overrideWithValue(const WorkbenchState()),
        agentStatusControllerProvider.overrideWithValue(
          const <String, AgentStatusEntry>{},
        ),
        agentProfilesProvider.overrideWith(_NoProfiles.new),
        settingsControllerProvider.overrideWithValue(.defaults),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () => chooseAgentTaskDispatchTarget(
                context,
                ref,
                request: const AgentTaskDispatchRequest(
                  workspaceId: 'workspace-1',
                  prompt: '',
                ),
                bindOnly: bindOnly,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a bind-only picker opens with no prompt to copy', (
    tester,
  ) async {
    await _openPicker(tester, bindOnly: true);
    expect(find.byType(AgentTaskDispatchDialog), findsOneWidget);
    expect(find.byTooltip('Copy Prompt'), findsNothing);
  });

  testWidgets('a dispatch picker still refuses an empty prompt', (
    tester,
  ) async {
    await _openPicker(tester, bindOnly: false);
    expect(find.byType(AgentTaskDispatchDialog), findsNothing);
  });
}
