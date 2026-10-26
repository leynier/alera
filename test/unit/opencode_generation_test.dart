import 'dart:io';

import 'package:alera/src/features/agent_profiles/application/opencode_generation_probe.dart';
import 'package:alera/src/features/agent_profiles/domain/opencode_generation.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_settings.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpenCodeGeneration', () {
    test('reads the generation from --version output', () {
      expect(
        OpenCodeGeneration.fromVersionOutput('1.19.4\n'),
        OpenCodeGeneration.v1,
      );
      expect(
        OpenCodeGeneration.fromVersionOutput('0.15.8'),
        OpenCodeGeneration.v1,
      );
      expect(
        OpenCodeGeneration.fromVersionOutput('opencode v2.1.4\n'),
        OpenCodeGeneration.v2,
      );
      expect(
        OpenCodeGeneration.fromVersionOutput('3.0.0'),
        OpenCodeGeneration.v2,
      );
      expect(OpenCodeGeneration.fromVersionOutput(''), isNull);
      expect(OpenCodeGeneration.fromVersionOutput('command not found'), isNull);
    });

    test('passes the thinking level the way each generation accepts', () {
      expect(
        openCodeRunArguments(
          model: 'opencode/x',
          thinkingLevel: 'high',
          generation: .v1,
        ),
        <String>[
          'run',
          '--model',
          'opencode/x',
          '--agent',
          'build',
          '--format',
          'default',
          '--variant',
          'high',
        ],
      );
      expect(
        openCodeRunArguments(
          model: 'opencode/x',
          thinkingLevel: 'high',
          generation: .v2,
        ),
        <String>[
          'run',
          '--model',
          'opencode/x#high',
          '--agent',
          'build',
          '--format',
          'default',
        ],
      );
    });

    test('the probe asks opencode once and falls back to v2', () async {
      final v1 = _VersionRunner(
        const ProcessRunOutput(exitCode: 0, stdout: '1.19.4\n', stderr: ''),
      );
      final probe = OpenCodeGenerationProbe(
        processRunner: v1,
        commandEnvironmentResolver: const _EmptyEnvironment(),
      );
      expect(await probe.detect(), OpenCodeGeneration.v1);
      expect(await probe.detect(), OpenCodeGeneration.v1);
      expect(v1.calls, 1);
      expect(v1.arguments, <String>['--version']);

      final missing = OpenCodeGenerationProbe(
        processRunner: _VersionRunner(null),
        commandEnvironmentResolver: const _EmptyEnvironment(),
      );
      expect(await missing.detect(), OpenCodeGeneration.v2);
    });
  });

  test('the desktop OpenCode plugin matches the one the runtime installs', () {
    final runtimePlugin = File(
      'rust/alera-cli/src/agent_status/integration_plugins/opencode.js',
    ).readAsStringSync();
    expect(aleraOpenCodeStatusPluginSource(), runtimePlugin);
  });

  group('retired opencode2 keys', () {
    test('either hook toggle enables OpenCode and the copy is kept', () {
      final legacy = AgentStatusHookSettings.fromJson(<String, Object?>{
        'opencode': false,
        'opencode2': true,
      });
      expect(legacy.opencode, isTrue);
      final encoded = const AgentStatusHookSettings(opencode: true).toMap();
      expect(encoded['opencode'], isTrue);
      expect(encoded['opencode2'], isTrue);
      expect(
        AgentStatusHookSettings.fromJson(<String, Object?>{'opencode': false})
            .opencode,
        isFalse,
      );
    });

    test('AI Assist settings read the retired agent as OpenCode', () {
      final settings = AiAssistSettings.fromJson(<String, Object?>{
        'agent': 'opencode2',
        'selectedModelByAgent': <String, Object?>{
          'opencode2': 'opencode/legacy',
          'codex': 'gpt-5.5',
        },
        'promptSettingsByOperation': <String, Object?>{
          'commitMessage': <String, Object?>{'agent': 'opencode2'},
        },
      });
      expect(settings.agent, AiAssistAgent.opencode);
      expect(settings.modelFor(.opencode), 'opencode/legacy');
      expect(settings.modelFor(.codex), 'gpt-5.5');
      expect(
        settings
            .promptSettingsByOperation[AiAssistOperation.commitMessage]
            ?.agent,
        AiAssistAgent.opencode,
      );
    });

    test('an existing OpenCode model wins over the retired one', () {
      final settings = AiAssistSettings.fromJson(<String, Object?>{
        'selectedModelByAgent': <String, Object?>{
          'opencode': 'opencode/current',
          'opencode2': 'opencode/legacy',
        },
      });
      expect(settings.modelFor(.opencode), 'opencode/current');
    });

    test('a text action override reads the retired agent as OpenCode', () {
      final action = TextAction.fromJson(<String, Object?>{
        'id': 'a',
        'name': 'Fix',
        'prompt': 'Fix it',
        'agentOverride': 'opencode2',
      });
      expect(action.agentOverride, AiAssistAgent.opencode);
    });
  });
}

class const _EmptyEnvironment() implements CommandEnvironmentResolver {
  @override
  Future<Map<String, String>> environment() async => const <String, String>{};

  @override
  Future<Map<String, String>> environmentVariables(List<String> names) async =>
      const <String, String>{};
}

class _VersionRunner(this._output) implements ProcessRunner {
  final ProcessRunOutput? _output;
  int calls = 0;
  List<String> arguments = const <String>[];

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls += 1;
    this.arguments = arguments;
    final output = _output;
    if (output == null) {
      throw ProcessException(executable, arguments, 'not found');
    }
    return output;
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) => throw UnimplementedError();
}
