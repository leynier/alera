import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/presentation/panes/agent_profiles_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'command_terminal_test_doubles.dart';

void main() {
  testWidgets('command profile tests its command in the embedded terminal', (
    tester,
  ) async {
    final runtime = FakeCommandTerminalRuntime(running: false);
    addTearDown(runtime.dispose);

    await _pumpPane(
      tester,
      runtime,
      _profile(launchMode: AgentProfileLaunchMode.command),
    );

    await tester.tap(find.text('Test Command'));
    await tester.pumpAndSettle();

    expect(find.text('Test Agent Profile'), findsOneWidget);
    expect(runtime.lastTab?.initialCommand, 'codex --model gpt-5.6-sol');

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(runtime.closedTabIds, <String>[runtime.lastTab!.id]);
  });

  testWidgets('managed profile tests its current command preview', (
    tester,
  ) async {
    final runtime = FakeCommandTerminalRuntime(running: false);
    addTearDown(runtime.dispose);

    await _pumpPane(
      tester,
      runtime,
      _profile(
        adapter: AgentType.amp,
        launchMode: AgentProfileLaunchMode.managed,
        managedConfig: const <String, Object?>{'mode': 'ultra', 'fast': true},
      ),
    );

    await tester.tap(find.text('Test Command'));
    await tester.pumpAndSettle();

    expect(find.text('Test Agent Profile'), findsOneWidget);
    expect(runtime.lastTab?.initialCommand, 'amp --mode ultra --fast');

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(runtime.closedTabIds, <String>[runtime.lastTab!.id]);
  });
}

AgentProfile _profile({
  required AgentProfileLaunchMode launchMode,
  AgentType adapter = AgentType.codex,
  Map<String, Object?> managedConfig = const <String, Object?>{},
}) {
  final now = DateTime.utc(2026, 8, 1);
  return AgentProfile(
    id: 'profile-1',
    name: 'Codex Sol',
    agentType: adapter.key,
    command: launchMode == AgentProfileLaunchMode.command
        ? 'codex --model gpt-5.6-sol'
        : adapter.key,
    launchMode: launchMode,
    managedConfig: managedConfig,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pumpPane(
  WidgetTester tester,
  FakeCommandTerminalRuntime runtime,
  AgentProfile profile,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentProfilesProvider.overrideWith(() => _TestAgentProfiles(profile)),
        settingsControllerProvider.overrideWith(
          () => _TestSettingsController(),
        ),
        terminalRuntimeProvider.overrideWithValue(runtime),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const Scaffold(
          body: SizedBox(
            width: 1200,
            height: 1000,
            child: AgentProfilesSettingsPane(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

class _TestAgentProfiles extends AgentProfiles {
  _TestAgentProfiles(this.profile);

  final AgentProfile profile;

  @override
  Future<List<AgentProfile>> build() async {
    return <AgentProfile>[profile];
  }
}

class _TestSettingsController extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;
}
