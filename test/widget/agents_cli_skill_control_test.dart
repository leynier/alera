import 'dart:ui' show PointerDeviceKind;

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_status/application/agent_hook_reconciliation_service.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_agent_canvas_skill_control.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_all_skills_control.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_computer_use_skill_control.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_emulator_skill_control.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_orchestration_skill_control.dart';
import 'package:alera/src/features/settings/presentation/panes/agents_cli_skill_control.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'command_terminal_test_doubles.dart';

void main() {
  testWidgets('skill control runs the selected runner in a terminal', (
    tester,
  ) async {
    final runtime = FakeCommandTerminalRuntime(running: false);
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final arguments = call.arguments as Map<dynamic, dynamic>;
            clipboardText = arguments['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [terminalRuntimeProvider.overrideWithValue(runtime)],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: AleraCliSkillControl(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(
      clipboardText,
      contains('--skill alera-cli --agent codex --global --yes'),
    );
    expect(runtime.lastTab, isNull);

    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(
      location: tester.getCenter(
        find.byType(PopupMenuButton<AleraCliSkillRunner>),
      ),
    );
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );

    await tester.tap(find.byType(PopupMenuButton<AleraCliSkillRunner>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('bunx').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(
      clipboardText,
      'bunx skills add https://github.com/leynier/alera --skill alera-cli --agent codex --global --yes',
    );
    expect(runtime.lastTab, isNull);

    await tester.tap(find.text('Install / Update'));
    await tester.pumpAndSettle();

    expect(find.text('Install Alera CLI Skill'), findsOneWidget);
    expect(
      runtime.lastTab?.initialCommand,
      'bunx skills add https://github.com/leynier/alera --skill alera-cli --agent codex --global --yes',
    );

    // The dialog owns the session: closing it terminates the shell tree.
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(runtime.closedTabIds, <String>[runtime.lastTab!.id]);
  });

  testWidgets('orchestration reapplies selected hooks after the terminal', (
    tester,
  ) async {
    final runtime = FakeCommandTerminalRuntime(running: false);
    final reconciler = _FakeHookReconciler();
    final settings = AleraSettings.defaults.copyWith(
      agents: AleraSettings.defaults.agents.copyWith(
        agentStatusHooks: const AgentStatusHookSettings(codex: true),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          terminalRuntimeProvider.overrideWithValue(runtime),
          agentHookReconciliationServiceProvider.overrideWithValue(reconciler),
          settingsControllerProvider.overrideWithValue(settings),
        ],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: AleraOrchestrationSkillControl(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Install / Update'));
    await tester.pumpAndSettle();

    expect(
      runtime.lastTab?.initialCommand,
      contains('--skill alera-orchestration'),
    );
    // The hooks are the half that stays in Dart, so nothing has run yet.
    expect(reconciler.settings, isNull);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(reconciler.settings?.codex, isTrue);
    expect(find.text('Selected hooks ready'), findsOneWidget);
  });

  testWidgets('emulator control installs the emulator skill', (tester) async {
    final runtime = FakeCommandTerminalRuntime(running: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [terminalRuntimeProvider.overrideWithValue(runtime)],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(body: AleraEmulatorSkillControl()),
        ),
      ),
    );

    await tester.tap(find.text('Install / Update'));
    await tester.pumpAndSettle();

    expect(runtime.lastTab?.initialCommand, contains('--skill alera-emulator'));
  });

  testWidgets('computer use control installs the computer use skill', (
    tester,
  ) async {
    final runtime = FakeCommandTerminalRuntime(running: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [terminalRuntimeProvider.overrideWithValue(runtime)],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(body: AleraComputerUseSkillControl()),
        ),
      ),
    );

    await tester.tap(find.text('Install / Update'));
    await tester.pumpAndSettle();

    expect(runtime.lastTab?.initialCommand, contains('--skill computer-use'));
  });

  testWidgets('Agent Canvas control installs the Agent Canvas skill', (
    tester,
  ) async {
    final runtime = FakeCommandTerminalRuntime(running: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [terminalRuntimeProvider.overrideWithValue(runtime)],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(body: AleraAgentCanvasSkillControl()),
        ),
      ),
    );

    await tester.tap(find.text('Install / Update'));
    await tester.pumpAndSettle();

    expect(
      runtime.lastTab?.initialCommand,
      aleraCliSkillInstallCommand(
        runner: AleraCliSkillRunner.auto,
        skill: AleraAgentSkill.agentCanvas,
      ),
    );
  });

  testWidgets('all skills control runs every skill in the embedded terminal', (
    tester,
  ) async {
    final runtime = FakeCommandTerminalRuntime(running: false);
    final service = _FakeAleraCliSkillService();
    final reconciler = _FakeHookReconciler();
    final settings = AleraSettings.defaults.copyWith(
      agents: AleraSettings.defaults.agents.copyWith(
        agentStatusHooks: const AgentStatusHookSettings(codex: true),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          terminalRuntimeProvider.overrideWithValue(runtime),
          aleraCliSkillServiceProvider.overrideWithValue(service),
          agentHookReconciliationServiceProvider.overrideWithValue(reconciler),
          settingsControllerProvider.overrideWithValue(settings),
        ],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(body: AleraAllSkillsControl()),
        ),
      ),
    );

    await tester.tap(find.text('Install / Update'));
    await tester.pumpAndSettle();

    expect(find.text('Install All Alera Skills'), findsOneWidget);
    final command = runtime.lastTab?.initialCommand;
    expect(command, isNotNull);
    for (final skill in AleraAgentSkill.values) {
      expect(
        command,
        contains('--skill ${skill.name} --agent codex --global --yes'),
      );
    }
    expect(command, isNot(contains('\n')));
    expect(service.skills, isEmpty);
    expect(reconciler.settings, isNull);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(reconciler.settings?.codex, isTrue);
    expect(find.text('Selected hooks ready'), findsOneWidget);
  });

  testWidgets('all skills control keeps its three buttons on one row', (
    tester,
  ) async {
    final fontLoader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await fontLoader.load();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(
            body: SizedBox(width: 360, child: AleraAllSkillsControl()),
          ),
        ),
      ),
    );

    final outlinedButtons = find.byType(OutlinedButton);
    final filledButton = find.byType(FilledButton);
    expect(outlinedButtons, findsNWidgets(2));
    expect(filledButton, findsOneWidget);

    final runnerY = tester.getTopLeft(outlinedButtons.at(0)).dy;
    expect(tester.getTopLeft(outlinedButtons.at(1)).dy, runnerY);
    expect(tester.getTopLeft(filledButton).dy, runnerY);
  });

  testWidgets('all skills control copies without opening the terminal', (
    tester,
  ) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final arguments = call.arguments as Map<dynamic, dynamic>;
            clipboardText = arguments['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final runtime = FakeCommandTerminalRuntime(running: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [terminalRuntimeProvider.overrideWithValue(runtime)],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(body: AleraAllSkillsControl()),
        ),
      ),
    );

    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(clipboardText, isNotNull);
    for (final skill in AleraAgentSkill.values) {
      expect(
        clipboardText,
        contains('--skill ${skill.name} --agent codex --global --yes'),
      );
    }
    expect(runtime.lastTab, isNull);
  });
}

class _FakeAleraCliSkillService extends AleraCliSkillService {
  _FakeAleraCliSkillService()
    : super(
        processRunner: _NoopProcessRunner(),
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
      );

  final List<AleraAgentSkill> skills = <AleraAgentSkill>[];

  @override
  Future<AleraCliSkillInstallResult> installOrUpdate({
    AleraCliSkillRunner runner = AleraCliSkillRunner.auto,
    AleraAgentSkill skill = AleraAgentSkill.cli,
  }) async {
    skills.add(skill);
    final attemptRunner = runner == AleraCliSkillRunner.auto
        ? AleraCliSkillRunner.npx
        : runner;
    return AleraCliSkillInstallResult(
      runner: runner,
      skill: skill,
      attempts: <AleraCliSkillInstallAttempt>[
        AleraCliSkillInstallAttempt(
          runner: attemptRunner,
          exitCode: 0,
          stdout: 'ok',
          stderr: '',
        ),
      ],
    );
  }
}

class _FakeHookReconciler implements AgentHookReconciler {
  AgentStatusHookSettings? settings;

  @override
  Future<List<ManagedAgentHookInstallStatus>> reconcile(
    AgentStatusHookSettings settings,
  ) async {
    this.settings = settings;
    return <ManagedAgentHookInstallStatus>[
      const ManagedAgentHookInstallStatus(
        agentType: AgentType.codex,
        state: ManagedAgentHookInstallState.installed,
        configPath: '/tmp/codex',
        managedHooksPresent: true,
      ),
    ];
  }
}

class _NoopProcessRunner implements ProcessRunner {
  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}

class _FakeCommandEnvironmentResolver implements CommandEnvironmentResolver {
  const _FakeCommandEnvironmentResolver();

  @override
  Future<Map<String, String>> environment() async => const <String, String>{};

  @override
  Future<Map<String, String>> environmentVariables(List<String> names) async =>
      const <String, String>{};
}
