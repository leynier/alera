import 'dart:async';
import 'dart:convert';

import 'package:alera/src/features/ai_assist/application/ai_assist_registry.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_process_failure.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

const int aiAssistModelDiscoveryTimeoutSeconds = 60;
const int aiAssistModelDiscoveryMaxOutputBytes = 4 * 1024 * 1024;

class const AiAssistModelDiscoveryResult({
  required final bool success,
  required final AiAssistAgent agent,
  required final List<AiAssistModel> models,
  required final String? defaultModelId,
  final String? error,
});

abstract interface class AiAssistModelDiscoveryService {
  Future<AiAssistModelDiscoveryResult> discover(AiAssistAgent agent);
}

class CliAiAssistModelDiscoveryService({
  required final ProcessRunner processRunner,
  CommandEnvironmentResolver? commandEnvironmentResolver,
}) implements AiAssistModelDiscoveryService {
  this
    : commandEnvironmentResolver =
          commandEnvironmentResolver ?? UserCommandEnvironmentResolver();

  final CommandEnvironmentResolver commandEnvironmentResolver;

  @override
  Future<AiAssistModelDiscoveryResult> discover(AiAssistAgent agent) async {
    final spec = aiAssistAgentSpecs[agent];
    if (spec == null) {
      return AiAssistModelDiscoveryResult(
        success: false,
        agent: agent,
        models: const <AiAssistModel>[],
        defaultModelId: 'custom',
        error: '${agent.label} does not support AI Assist.',
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
      return AiAssistModelDiscoveryResult(
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
        const Duration(seconds: aiAssistModelDiscoveryTimeoutSeconds),
        onTimeout: () {
          process.kill();
          throw TimeoutException(
            '${spec.label} model discovery timed out after ${aiAssistModelDiscoveryTimeoutSeconds}s.',
          );
        },
      );
      return _finalize(spec, output);
    } on TimeoutException catch (error) {
      return AiAssistModelDiscoveryResult(
        success: false,
        agent: agent,
        models: spec.models,
        defaultModelId: spec.defaultModelId,
        error: error.message,
      );
    } on _AiAssistModelDiscoveryOutputLimitException {
      process.kill();
      return AiAssistModelDiscoveryResult(
        success: false,
        agent: agent,
        models: spec.models,
        defaultModelId: spec.defaultModelId,
        error: '${spec.label} returned too much model data.',
      );
    }
  }

  AiAssistModelDiscoveryResult _staticResult(AiAssistAgentSpec spec) {
    return AiAssistModelDiscoveryResult(
      success: true,
      agent: spec.agent,
      models: spec.models,
      defaultModelId: spec.defaultModelId,
    );
  }

  AiAssistModelDiscoveryResult _finalize(
    AiAssistAgentSpec spec,
    ProcessRunOutput output,
  ) {
    if (output.exitCode != 0) {
      final detail = aiAssistProcessFailureDetail(output.stdout, output.stderr);
      return AiAssistModelDiscoveryResult(
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
      return AiAssistModelDiscoveryResult(
        success: false,
        agent: spec.agent,
        models: const <AiAssistModel>[],
        defaultModelId: spec.defaultModelId,
        error: '${spec.label} returned no available models.',
      );
    }
    final defaultModelId =
        spec.defaultModelId != null &&
            models.any((model) => model.id == spec.defaultModelId)
        ? spec.defaultModelId
        : spec.modelCanInherit
        ? null
        : models.first.id;
    return AiAssistModelDiscoveryResult(
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
        if (totalBytes > aiAssistModelDiscoveryMaxOutputBytes) {
          process.kill();
          throw const _AiAssistModelDiscoveryOutputLimitException();
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
}

class const _AiAssistModelDiscoveryOutputLimitException() implements Exception;
