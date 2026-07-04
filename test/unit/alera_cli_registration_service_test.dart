import 'dart:io';

import 'package:alera/src/features/settings/infra/alera_cli_registration_service.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/alera_cli_sidecar.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AleraCliRegistrationService', () {
    test('installs a POSIX wrapper into user bin', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-cli-registration-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final home = Directory(p.join(tempDir.path, 'home'));
      final support = Directory(p.join(tempDir.path, 'support'));
      final userBin = p.join(home.path, '.local', 'bin');
      final service = AleraCliRegistrationService(
        cliResolver: const _FakeAleraCliResolver(
          AleraCliCommand(executable: '/Applications/Alera.app/alera'),
        ),
        commandEnvironmentResolver: _FakeCommandEnvironmentResolver(
          <String, String>{'PATH': '$userBin:/usr/bin'},
        ),
        processRunner: _FakeProcessRunner(),
        applicationSupportDirectory: () async => support,
        operatingSystem: 'macos',
        homePath: home.path,
      );

      final initial = await service.status();
      expect(initial.state, AleraCliRegistrationState.notInstalled);
      expect(initial.pathConfigured, isTrue);

      final installed = await service.installOrUpdate();

      expect(installed.ready, isTrue);
      expect(installed.commandPath, p.join(userBin, 'alera'));
      final wrapper = await File(installed.commandPath!).readAsString();
      expect(wrapper, startsWith('#!/bin/sh'));
      expect(wrapper, contains('ALERA_CLI_WRAPPER=1'));
      expect(
        wrapper,
        contains(
          "export ALERA_RUNTIME_DIR='${p.join(support.path, 'terminal_host')}'",
        ),
      );
      expect(wrapper, contains("exec '/Applications/Alera.app/alera'"));
    });

    test('reports conflict without replacing existing command', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-cli-registration-conflict-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final home = Directory(p.join(tempDir.path, 'home'));
      final support = Directory(p.join(tempDir.path, 'support'));
      final commandPath = p.join(home.path, '.local', 'bin', 'alera');
      await File(commandPath).parent.create(recursive: true);
      await File(commandPath).writeAsString('third-party command\n');
      final service = AleraCliRegistrationService(
        cliResolver: const _FakeAleraCliResolver(
          AleraCliCommand(executable: '/Applications/Alera.app/alera'),
        ),
        commandEnvironmentResolver: _FakeCommandEnvironmentResolver(
          <String, String>{'PATH': p.dirname(commandPath)},
        ),
        processRunner: _FakeProcessRunner(),
        applicationSupportDirectory: () async => support,
        operatingSystem: 'macos',
        homePath: home.path,
      );

      final status = await service.installOrUpdate();

      expect(status.state, AleraCliRegistrationState.conflict);
      expect(await File(commandPath).readAsString(), 'third-party command\n');
    });

    test('reports conflict when another command wins PATH lookup', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-cli-registration-shadow-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final home = Directory(p.join(tempDir.path, 'home'));
      final support = Directory(p.join(tempDir.path, 'support'));
      final shadowDir = Directory(p.join(tempDir.path, 'shadow-bin'));
      await shadowDir.create(recursive: true);
      final shadowCommand = File(p.join(shadowDir.path, 'alera'));
      await shadowCommand.writeAsString('shadow command\n');
      await Process.run('chmod', <String>['755', shadowCommand.path]);
      final userBin = p.join(home.path, '.local', 'bin');
      final service = AleraCliRegistrationService(
        cliResolver: const _FakeAleraCliResolver(
          AleraCliCommand(executable: '/Applications/Alera.app/alera'),
        ),
        commandEnvironmentResolver: _FakeCommandEnvironmentResolver(
          <String, String>{'PATH': '${shadowDir.path}:$userBin:/usr/bin'},
        ),
        processRunner: _FakeProcessRunner(),
        applicationSupportDirectory: () async => support,
        operatingSystem: 'macos',
        homePath: home.path,
      );

      final installed = await service.installOrUpdate();

      expect(installed.state, AleraCliRegistrationState.conflict);
      expect(installed.ready, isFalse);
      expect(installed.detail, contains(shadowCommand.path));
      expect(installed.detail, contains('Earlier On PATH'));
    });

    test('ignores non-executable POSIX commands when resolving PATH', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-cli-registration-non-executable-shadow-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final home = Directory(p.join(tempDir.path, 'home'));
      final support = Directory(p.join(tempDir.path, 'support'));
      final shadowDir = Directory(p.join(tempDir.path, 'shadow-bin'));
      await shadowDir.create(recursive: true);
      final shadowCommand = File(p.join(shadowDir.path, 'alera'));
      await shadowCommand.writeAsString('shadow command\n');
      final userBin = p.join(home.path, '.local', 'bin');
      final service = AleraCliRegistrationService(
        cliResolver: const _FakeAleraCliResolver(
          AleraCliCommand(executable: '/Applications/Alera.app/alera'),
        ),
        commandEnvironmentResolver: _FakeCommandEnvironmentResolver(
          <String, String>{'PATH': '${shadowDir.path}:$userBin:/usr/bin'},
        ),
        processRunner: _FakeProcessRunner(),
        applicationSupportDirectory: () async => support,
        operatingSystem: 'macos',
        homePath: home.path,
      );

      final installed = await service.installOrUpdate();

      expect(installed.ready, isTrue);
      expect(installed.state, AleraCliRegistrationState.installed);
      expect(installed.detail, isNot(contains('Earlier On PATH')));
    });

    test('refresh uses a fresh PATH environment', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-cli-registration-refresh-path-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final home = Directory(p.join(tempDir.path, 'home'));
      final support = Directory(p.join(tempDir.path, 'support'));
      final userBin = p.join(home.path, '.local', 'bin');
      var environment = const <String, String>{'PATH': '/usr/bin'};
      final service = AleraCliRegistrationService(
        cliResolver: const _FakeAleraCliResolver(
          AleraCliCommand(executable: '/Applications/Alera.app/alera'),
        ),
        commandEnvironmentResolverFactory: () =>
            _FakeCommandEnvironmentResolver(environment),
        processRunner: _FakeProcessRunner(),
        applicationSupportDirectory: () async => support,
        operatingSystem: 'macos',
        homePath: home.path,
      );

      final installed = await service.installOrUpdate();
      expect(installed.state, AleraCliRegistrationState.installed);
      expect(installed.ready, isFalse);

      environment = <String, String>{'PATH': '$userBin:/usr/bin'};
      final refreshed = await service.status();

      expect(refreshed.ready, isTrue);
      expect(refreshed.state, AleraCliRegistrationState.installed);
    });

    test('reports stale when POSIX wrapper is not executable', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-cli-registration-permission-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final home = Directory(p.join(tempDir.path, 'home'));
      final support = Directory(p.join(tempDir.path, 'support'));
      final userBin = p.join(home.path, '.local', 'bin');
      final service = AleraCliRegistrationService(
        cliResolver: const _FakeAleraCliResolver(
          AleraCliCommand(executable: '/Applications/Alera.app/alera'),
        ),
        commandEnvironmentResolver: _FakeCommandEnvironmentResolver(
          <String, String>{'PATH': '$userBin:/usr/bin'},
        ),
        processRunner: const _FakeProcessRunner(applyChmod: false),
        applicationSupportDirectory: () async => support,
        operatingSystem: 'macos',
        homePath: home.path,
      );

      final installed = await service.installOrUpdate();

      expect(installed.state, AleraCliRegistrationState.stale);
      expect(installed.ready, isFalse);
      expect(installed.detail, contains('Is Not Executable'));
    });

    test('writes a Windows command wrapper under local app data', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-cli-registration-windows-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final support = Directory(p.join(tempDir.path, 'support'));
      final localAppData = p.join(tempDir.path, 'LocalAppData');
      final commandDir = p.join(localAppData, 'Programs', 'Alera', 'bin');
      final service = AleraCliRegistrationService(
        cliResolver: const _FakeAleraCliResolver(
          AleraCliCommand(executable: r'C:\Program Files\Alera\alera.exe'),
        ),
        commandEnvironmentResolver: _FakeCommandEnvironmentResolver(
          <String, String>{'Path': '$commandDir;C:\\Windows'},
        ),
        processRunner: _FakeProcessRunner(),
        applicationSupportDirectory: () async => support,
        operatingSystem: 'windows',
        localAppDataPath: localAppData,
      );

      final installed = await service.installOrUpdate();

      expect(installed.ready, isTrue);
      expect(installed.commandPath, p.join(commandDir, 'alera.cmd'));
      final wrapper = await File(installed.commandPath!).readAsString();
      expect(wrapper, startsWith('@echo off'));
      expect(wrapper, contains('rem ALERA_CLI_WRAPPER=1'));
      expect(wrapper, contains('set "ALERA_RUNTIME_DIR='));
      expect(wrapper, contains(r'"C:\Program Files\Alera\alera.exe"  %*'));
    });

    test(
      'reports conflict when another Windows command wins PATH lookup',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'alera-cli-registration-windows-shadow-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        final support = Directory(p.join(tempDir.path, 'support'));
        final localAppData = p.join(tempDir.path, 'LocalAppData');
        final commandDir = p.join(localAppData, 'Programs', 'Alera', 'bin');
        final shadowDir = Directory(p.join(tempDir.path, 'shadow-bin'));
        await shadowDir.create(recursive: true);
        final shadowCommand = File(p.join(shadowDir.path, 'alera.exe'));
        await shadowCommand.writeAsString('shadow command\n');
        final service = AleraCliRegistrationService(
          cliResolver: const _FakeAleraCliResolver(
            AleraCliCommand(executable: r'C:\Program Files\Alera\alera.exe'),
          ),
          commandEnvironmentResolver: _FakeCommandEnvironmentResolver(
            <String, String>{
              'Path': '${shadowDir.path};$commandDir;C:\\Windows',
            },
          ),
          processRunner: _FakeProcessRunner(),
          applicationSupportDirectory: () async => support,
          operatingSystem: 'windows',
          localAppDataPath: localAppData,
        );

        final installed = await service.installOrUpdate();

        expect(installed.state, AleraCliRegistrationState.conflict);
        expect(installed.ready, isFalse);
        expect(installed.detail, contains(shadowCommand.path));
      },
    );
  });
}

class _FakeAleraCliResolver implements AleraCliResolver {
  const _FakeAleraCliResolver(this._command);

  final AleraCliCommand _command;

  @override
  Future<AleraCliCommand> resolve({required String runtimeDir}) async {
    return _command;
  }
}

class _FakeCommandEnvironmentResolver implements CommandEnvironmentResolver {
  const _FakeCommandEnvironmentResolver(this._environment);

  final Map<String, String> _environment;

  @override
  Future<Map<String, String>> environment() async => _environment;
}

class _FakeProcessRunner implements ProcessRunner {
  const _FakeProcessRunner({this.applyChmod = true});

  final bool applyChmod;

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (applyChmod && executable == 'chmod') {
      final result = await Process.run(executable, arguments);
      return ProcessRunOutput(
        exitCode: result.exitCode,
        stdout: result.stdout as String,
        stderr: result.stderr as String,
      );
    }
    return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
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
