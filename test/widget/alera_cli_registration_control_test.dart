import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/settings/infra/alera_cli_registration_service.dart';
import 'package:alera/src/features/settings/presentation/panes/agents_cli_skill_control.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    expect(find.textContaining('Registration check failed'), findsOneWidget);
    expect(find.textContaining('missing'), findsOneWidget);
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

    expect(find.textContaining('Registration failed'), findsOneWidget);
    expect(find.textContaining('permission denied'), findsOneWidget);
  });
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
    bool includeParentEnvironment = true,
  }) {
    throw UnimplementedError();
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
  detail: 'Register the Alera command to use it from terminals and agents.',
);
