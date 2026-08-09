import 'dart:async';
import 'dart:convert';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

class AgentProfilePersonaDiscoveryResult {
  const AgentProfilePersonaDiscoveryResult({
    required this.personas,
    this.error,
  });

  final List<String> personas;
  final String? error;
}

class AgentProfilePersonaDiscovery {
  AgentProfilePersonaDiscovery({
    required this.processRunner,
    required this.commandEnvironmentResolver,
  });

  static const Duration _timeout = Duration(seconds: 30);
  static const int _maxOutputBytes = 1024 * 1024;

  final ProcessRunner processRunner;
  final CommandEnvironmentResolver commandEnvironmentResolver;

  Future<AgentProfilePersonaDiscoveryResult> discover(AgentType adapter) async {
    final command = switch (adapter) {
      AgentType.agy => (executable: 'agy', arguments: const <String>['agents']),
      AgentType.opencode => (
        executable: 'opencode',
        arguments: const <String>['agent', 'list'],
      ),
      AgentType.opencode2 => (
        executable: 'opencode2',
        arguments: const <String>['agent', 'list'],
      ),
      _ => null,
    };
    if (command == null) {
      return const AgentProfilePersonaDiscoveryResult(personas: <String>[]);
    }

    final StartedProcess process;
    try {
      process = await processRunner.start(
        command.executable,
        command.arguments,
        environment: await commandEnvironmentResolver.environment(),
      );
    } catch (_) {
      return AgentProfilePersonaDiscoveryResult(
        personas: const <String>[],
        error: '${command.executable} persona discovery could not be started.',
      );
    }

    try {
      final output = await _collect(process).timeout(
        _timeout,
        onTimeout: () {
          process.kill();
          throw TimeoutException('Persona discovery timed out.');
        },
      );
      if (output.exitCode != 0) {
        return AgentProfilePersonaDiscoveryResult(
          personas: const <String>[],
          error: 'Persona discovery failed for ${adapter.key}.',
        );
      }
      final personas = switch (adapter) {
        AgentType.agy => _parseAgy(output.stdout),
        AgentType.opencode ||
        AgentType.opencode2 => _parseOpenCode(output.stdout),
        _ => const <String>[],
      };
      return AgentProfilePersonaDiscoveryResult(personas: personas);
    } on TimeoutException catch (error) {
      return AgentProfilePersonaDiscoveryResult(
        personas: const <String>[],
        error: error.message,
      );
    } on _PersonaOutputLimitException {
      process.kill();
      return const AgentProfilePersonaDiscoveryResult(
        personas: <String>[],
        error: 'Persona discovery returned too much data.',
      );
    }
  }

  Future<ProcessRunOutput> _collect(StartedProcess process) async {
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    var totalBytes = 0;

    Future<void> collect(Stream<List<int>> stream, StringBuffer buffer) async {
      await for (final chunk in stream) {
        totalBytes += chunk.length;
        if (totalBytes > _maxOutputBytes) {
          process.kill();
          throw const _PersonaOutputLimitException();
        }
        buffer.write(utf8.decode(chunk, allowMalformed: true));
      }
    }

    final stdoutDone = collect(process.stdout, stdout);
    final stderrDone = collect(process.stderr, stderr);
    final exitCode = await process.exitCode;
    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
    return ProcessRunOutput(
      exitCode: exitCode,
      stdout: stdout.toString(),
      stderr: stderr.toString(),
    );
  }

  List<String> _parseAgy(String output) {
    return _unique(
      output
          .split(RegExp(r'\r?\n'))
          .map((line) => line.replaceFirst(RegExp(r'^\s*[-*]\s*'), '').trim())
          .where(
            (line) =>
                line.isNotEmpty &&
                line.toLowerCase() != 'available agents:' &&
                RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(line),
          ),
    );
  }

  List<String> _parseOpenCode(String output) {
    return _unique(
      output
          .split(RegExp(r'\r?\n'))
          .map(
            (line) => RegExp(
              r'^\s*([A-Za-z0-9_.-]+)\s+\((?:primary|subagent|all)\)',
            ).firstMatch(line)?.group(1),
          )
          .whereType<String>(),
    );
  }

  List<String> _unique(Iterable<String> values) {
    final seen = <String>{};
    return <String>[
      for (final value in values)
        if (seen.add(value)) value,
    ];
  }
}

class _PersonaOutputLimitException implements Exception {
  const _PersonaOutputLimitException();
}
