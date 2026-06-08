import 'dart:async';
import 'dart:convert';

import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_registry.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

const int aiTextModelDiscoveryTimeoutSeconds = 60;
const int aiTextModelDiscoveryMaxOutputBytes = 4 * 1024 * 1024;

class AiTextModelDiscoveryResult {
  const AiTextModelDiscoveryResult({
    required this.success,
    required this.agent,
    required this.models,
    required this.defaultModelId,
    this.error,
  });

  final bool success;
  final AiTextGenerationAgent agent;
  final List<AiTextModel> models;
  final String defaultModelId;
  final String? error;
}

abstract interface class AiTextModelDiscoveryService {
  Future<AiTextModelDiscoveryResult> discover(AiTextGenerationAgent agent);
}

class CliAiTextModelDiscoveryService implements AiTextModelDiscoveryService {
  CliAiTextModelDiscoveryService({
    required this.processRunner,
    CommandEnvironmentResolver? commandEnvironmentResolver,
  }) : commandEnvironmentResolver =
           commandEnvironmentResolver ?? UserCommandEnvironmentResolver();

  final ProcessRunner processRunner;
  final CommandEnvironmentResolver commandEnvironmentResolver;

  @override
  Future<AiTextModelDiscoveryResult> discover(
    AiTextGenerationAgent agent,
  ) async {
    final spec = aiTextAgentSpecs[agent];
    if (spec == null) {
      return AiTextModelDiscoveryResult(
        success: false,
        agent: agent,
        models: const <AiTextModel>[],
        defaultModelId: 'custom',
        error: '${agent.label} does not support AI text generation.',
      );
    }
    if (spec.modelsCommand == null) {
      return _staticResult(spec);
    }

    final StartedProcess process;
    try {
      process = await processRunner.start(
        spec.binary,
        spec.modelsCommand!,
        environment: await commandEnvironmentResolver.environment(),
      );
    } catch (_) {
      return AiTextModelDiscoveryResult(
        success: false,
        agent: agent,
        models: spec.models,
        defaultModelId: spec.defaultModelId,
        error:
            '${spec.label} model discovery could not be started. Check that ${spec.binary} is installed and on PATH.',
      );
    }

    try {
      final output = await _collectProcess(process).timeout(
        const Duration(seconds: aiTextModelDiscoveryTimeoutSeconds),
        onTimeout: () {
          process.kill();
          throw TimeoutException(
            '${spec.label} model discovery timed out after ${aiTextModelDiscoveryTimeoutSeconds}s.',
          );
        },
      );
      return _finalize(spec, output);
    } on TimeoutException catch (error) {
      return AiTextModelDiscoveryResult(
        success: false,
        agent: agent,
        models: spec.models,
        defaultModelId: spec.defaultModelId,
        error: error.message,
      );
    } on _AiTextModelDiscoveryOutputLimitException {
      process.kill();
      return AiTextModelDiscoveryResult(
        success: false,
        agent: agent,
        models: spec.models,
        defaultModelId: spec.defaultModelId,
        error: '${spec.label} returned too much model data.',
      );
    }
  }

  AiTextModelDiscoveryResult _staticResult(AiTextAgentSpec spec) {
    return AiTextModelDiscoveryResult(
      success: true,
      agent: spec.agent,
      models: spec.models,
      defaultModelId: spec.defaultModelId,
    );
  }

  AiTextModelDiscoveryResult _finalize(
    AiTextAgentSpec spec,
    ProcessRunOutput output,
  ) {
    if (output.exitCode != 0) {
      final detail = _failureDetail(output.stdout, output.stderr);
      return AiTextModelDiscoveryResult(
        success: false,
        agent: spec.agent,
        models: spec.models,
        defaultModelId: spec.defaultModelId,
        error: detail == null
            ? '${spec.label} model discovery failed. Check the agent CLI configuration and try again.'
            : '${spec.label} model discovery failed: $detail',
      );
    }

    var models = spec.parseModels(output.stdout);
    if (models.isEmpty && output.stderr.trim().isNotEmpty) {
      models = spec.parseModels(output.stderr);
    }
    if (models.isEmpty) {
      if (spec.models.isNotEmpty) {
        return _staticResult(spec);
      }
      return AiTextModelDiscoveryResult(
        success: false,
        agent: spec.agent,
        models: const <AiTextModel>[],
        defaultModelId: spec.defaultModelId,
        error: '${spec.label} returned no available models.',
      );
    }
    final defaultModelId =
        models.any((model) => model.id == spec.defaultModelId)
        ? spec.defaultModelId
        : models.first.id;
    return AiTextModelDiscoveryResult(
      success: true,
      agent: spec.agent,
      models: models,
      defaultModelId: defaultModelId,
    );
  }

  Future<ProcessRunOutput> _collectProcess(StartedProcess process) async {
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    var totalBytes = 0;

    Future<void> collect(Stream<List<int>> stream, StringBuffer buffer) async {
      await for (final chunk in stream) {
        totalBytes += chunk.length;
        if (totalBytes > aiTextModelDiscoveryMaxOutputBytes) {
          process.kill();
          throw const _AiTextModelDiscoveryOutputLimitException();
        }
        buffer.write(utf8.decode(chunk));
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

  String? _failureDetail(String stdout, String stderr) {
    final combined = '$stdout\n$stderr'
        .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
        .trim();
    if (combined.isEmpty) {
      return null;
    }
    final lines = combined
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    final detail = lines.isEmpty ? combined : lines.last.trim();
    return detail.length > 240
        ? '${detail.substring(0, 240).trimRight()}...'
        : detail;
  }
}

class _AiTextModelDiscoveryOutputLimitException implements Exception {
  const _AiTextModelDiscoveryOutputLimitException();
}
