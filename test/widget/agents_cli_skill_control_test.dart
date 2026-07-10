import 'dart:ui' show PointerDeviceKind;

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_status/application/agent_hook_reconciliation_service.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/alera_cli_registration_service.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_orchestration_skill_control.dart';
import 'package:alera/src/features/settings/presentation/panes/agents_cli_skill_control.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('skill control copies and runs the selected runner', (
    tester,
  ) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final arguments = call.arguments as Map<dynamic, dynamic>;
            clipboardText = arguments['text'] as String?;
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': clipboardText};
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final service = _FakeAleraCliSkillService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aleraCliSkillServiceProvider.overrideWithValue(service)],
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

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(
      clipboardText,
      'npx skills add https://github.com/leynier/alera --skill alera-cli --global || bunx skills add https://github.com/leynier/alera --skill alera-cli --global',
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
      'bunx skills add https://github.com/leynier/alera --skill alera-cli --global',
    );

    await tester.tap(find.text('Install / Update'));
    await tester.pump();
    await tester.pump();

    expect(service.runner, AleraCliSkillRunner.bunx);
    expect(find.text('Install Complete (bunx)'), findsOneWidget);
  });

  testWidgets('registration control surfaces refresh failures', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aleraCliRegistrationServiceProvider.overrideWithValue(
            _FakeAleraCliRegistrationService(
              statusError: StateError('missing'),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: AleraCliRegistrationControl(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Registration Check Failed'), findsOneWidget);
    expect(find.textContaining('missing'), findsOneWidget);
  });

  testWidgets('orchestration install reapplies selected hooks', (tester) async {
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
          aleraCliSkillServiceProvider.overrideWithValue(service),
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
    await tester.pump();
    await tester.pump();

    expect(service.skill, AleraAgentSkill.orchestration);
    expect(reconciler.settings?.codex, isTrue);
    expect(
      find.text('Install Complete (npx) · Selected Hooks Ready'),
      findsOneWidget,
    );
  });

  testWidgets('registration control surfaces install failures', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aleraCliRegistrationServiceProvider.overrideWithValue(
            _FakeAleraCliRegistrationService(
              installError: StateError('permission denied'),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: AleraCliRegistrationControl(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Register'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Registration Failed'), findsOneWidget);
    expect(find.textContaining('permission denied'), findsOneWidget);
  });
}

class _FakeAleraCliSkillService extends AleraCliSkillService {
  _FakeAleraCliSkillService()
    : super(
        processRunner: _NoopProcessRunner(),
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
      );

  AleraCliSkillRunner? runner;
  AleraAgentSkill? skill;

  @override
  Future<AleraCliSkillInstallResult> installOrUpdate({
    AleraCliSkillRunner runner = AleraCliSkillRunner.auto,
    AleraAgentSkill skill = AleraAgentSkill.cli,
  }) async {
    this.runner = runner;
    this.skill = skill;
    final attemptRunner = runner == AleraCliSkillRunner.auto
        ? AleraCliSkillRunner.npx
        : runner;
    return AleraCliSkillInstallResult(
      runner: runner,
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

class _FakeAleraCliRegistrationService extends AleraCliRegistrationService {
  _FakeAleraCliRegistrationService({this.statusError, this.installError})
    : super(processRunner: _NoopProcessRunner());

  final Object? statusError;
  final Object? installError;

  @override
  Future<AleraCliRegistrationStatus> status() async {
    final error = statusError;
    if (error != null) {
      throw error;
    }
    return _notRegisteredStatus;
  }

  @override
  Future<AleraCliRegistrationStatus> installOrUpdate() async {
    final error = installError;
    if (error != null) {
      throw error;
    }
    return _notRegisteredStatus;
  }
}

const _notRegisteredStatus = AleraCliRegistrationStatus(
  commandName: 'alera',
  commandPath: '/Users/test/.local/bin/alera',
  pathDirectory: '/Users/test/.local/bin',
  pathConfigured: false,
  launcherPath: '/Applications/Alera.app/alera',
  installMethod: AleraCliRegistrationInstallMethod.wrapper,
  state: AleraCliRegistrationState.notInstalled,
  detail: 'Register The Alera Command To Use It From Terminals And Agents.',
);

class _FakeCommandEnvironmentResolver implements CommandEnvironmentResolver {
  const _FakeCommandEnvironmentResolver();

  @override
  Future<Map<String, String>> environment() async => const <String, String>{};
}
