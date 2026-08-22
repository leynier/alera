import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/ai_text_generation/application/ai_text_diff_only_execution.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_errors.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_prompt.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_registry.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_process_failure.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;

part 'ai_text_agent_command_plan.dart';

enum AgentTaskAccessPolicy { repositoryReadOnly, diffOnly }

enum AgentTaskOutputContract { plainText, readingDiffPlanV1 }

class AiTextAgentRunRequest {
  const AiTextAgentRunRequest({
    required this.settings,
    required this.prompt,
    required this.runId,
    required this.workingDirectory,
    this.agent,
    this.model,
    this.reasoning,
    this.cleanOutput = cleanGeneratedText,
    this.accessPolicy = AgentTaskAccessPolicy.repositoryReadOnly,
    this.outputContract = AgentTaskOutputContract.plainText,
    this.outputSchema,
  });

  final AiTextGenerationSettings settings;
  final String prompt;
  final String runId;
  final String? workingDirectory;
  final AiTextGenerationAgent? agent;
  final String? model;
  final String? reasoning;
  final String Function(String) cleanOutput;
  final AgentTaskAccessPolicy accessPolicy;
  final AgentTaskOutputContract outputContract;
  final String? outputSchema;
}

class AiTextAgentRunResult {
  const AiTextAgentRunResult({required this.text, required this.agentLabel});

  final String text;
  final String agentLabel;
}

abstract interface class AgentTaskRunner {
  Future<AiTextAgentRunResult> run(AiTextAgentRunRequest request);

  void cancel(String runId);
}

abstract interface class AiTextAgentRunner implements AgentTaskRunner {}

class CliAiTextAgentRunner implements AiTextAgentRunner {
  CliAiTextAgentRunner({
    required this.processRunner,
    CommandEnvironmentResolver? commandEnvironmentResolver,
  }) : commandEnvironmentResolver =
           commandEnvironmentResolver ?? UserCommandEnvironmentResolver();

  final ProcessRunner processRunner;
  final CommandEnvironmentResolver commandEnvironmentResolver;
  final Map<String, StartedProcess> _running = <String, StartedProcess>{};
  final Set<String> _pending = <String>{};
  final Set<String> _canceled = <String>{};

  @override
  Future<AiTextAgentRunResult> run(AiTextAgentRunRequest request) async {
    if (_pending.contains(request.runId) ||
        _running.containsKey(request.runId)) {
      throw const AiTextGenerationException('Generation is already running.');
    }
    _canceled.remove(request.runId);
    _pending.add(request.runId);

    _AiTextAgentCommandPlan? plan;
    Directory? isolatedDirectory;
    Future<int>? processExit;
    try {
      var environment = await commandEnvironmentResolver.environment();
      final requestedAgent = request.agent ?? request.settings.agent;
      if (request.accessPolicy == AgentTaskAccessPolicy.diffOnly &&
          requestedAgent == AiTextGenerationAgent.codex) {
        final missing = codexDiffOnlyEnvironmentVariableNames
            .where((name) => !environment.containsKey(name))
            .toList(growable: false);
        final hydrated = await commandEnvironmentResolver.environmentVariables(
          missing,
        );
        environment = <String, String>{...hydrated, ...environment};
      }
      plan = await _planCommand(request, environment);
      if (request.accessPolicy == AgentTaskAccessPolicy.diffOnly) {
        isolatedDirectory = await Directory.systemTemp.createTemp(
          'alera-diff-only-',
        );
      }
      if (_canceled.contains(request.runId)) {
        throw const AiTextGenerationCanceledException();
      }
      final StartedProcess process;
      try {
        process = await processRunner.start(
          plan.binary,
          plan.args,
          workingDirectory: isolatedDirectory?.path ?? request.workingDirectory,
          environment: <String, String>{
            ...(plan.exactEnvironment ?? environment),
            if (plan.exactEnvironment == null) ...plan.environmentOverrides,
          },
          includeParentEnvironment: plan.exactEnvironment == null,
        );
      } catch (_) {
        throw AiTextGenerationException(
          '${plan.label} could not be started. Check that ${plan.binary} is installed and on PATH.',
        );
      }
      processExit = process.exitCode;
      if (_canceled.contains(request.runId)) {
        process.kill();
        throw const AiTextGenerationCanceledException();
      }
      _pending.remove(request.runId);
      _running[request.runId] = process;
      if (plan.stdinPayload != null) {
        process.stdinWrite(utf8.encode(plan.stdinPayload!));
        process.stdinClose();
      }
      final output = await _collectProcess(process).timeout(
        Duration(seconds: request.settings.timeoutSeconds),
        onTimeout: () {
          process.kill();
          throw AiTextGenerationException(
            'Generation timed out after ${request.settings.timeoutSeconds}s.',
          );
        },
      );
      if (_canceled.contains(request.runId)) {
        throw const AiTextGenerationCanceledException();
      }
      if (output.exitCode != 0) {
        final detail = aiTextProcessFailureDetail(output.stdout, output.stderr);
        throw AiTextGenerationException(
          detail == null
              ? '${plan.label} failed. Check the agent CLI configuration and try again.'
              : '${plan.label} failed: $detail',
        );
      }
      final rawOutput = plan.outputFile == null
          ? output.stdout
          : await plan.outputFile!.readAsString();
      final text = request.outputContract == AgentTaskOutputContract.plainText
          ? request.cleanOutput(rawOutput)
          : _cleanStructuredOutput(request.cleanOutput(rawOutput));
      if (text.trim().isEmpty) {
        throw AiTextGenerationException('${plan.label} returned no text.');
      }
      return AiTextAgentRunResult(text: text, agentLabel: plan.label);
    } finally {
      _pending.remove(request.runId);
      _running.remove(request.runId);
      _canceled.remove(request.runId);
      await _waitForProcessExit(processExit);
      await plan?.dispose();
      final directory = isolatedDirectory;
      if (directory != null) {
        await _deleteTemporaryDirectory(directory);
      }
    }
  }

  @override
  void cancel(String runId) {
    if (!_pending.contains(runId) && !_running.containsKey(runId)) {
      return;
    }
    _canceled.add(runId);
    _running[runId]?.kill();
  }

  Future<ProcessRunOutput> _collectProcess(StartedProcess process) async {
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final stdoutDone = utf8.decoder.bind(process.stdout).forEach(stdout.write);
    final stderrDone = utf8.decoder.bind(process.stderr).forEach(stderr.write);
    final exitCode = await process.exitCode;
    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
    return ProcessRunOutput(
      exitCode: exitCode,
      stdout: stdout.toString(),
      stderr: stderr.toString(),
    );
  }

  String _cleanStructuredOutput(String output) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final structured = decoded['structured_output'];
        if (structured is Map || structured is List) {
          return jsonEncode(structured);
        }
        final result = decoded['result'];
        if (result is String && result.trim().isNotEmpty) {
          return _cleanStructuredOutput(result);
        }
        return jsonEncode(decoded);
      }
    } catch (_) {}
    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    ).firstMatch(trimmed);
    return fenced?.group(1)?.trim() ?? trimmed;
  }
}

Future<void> _waitForProcessExit(Future<int>? processExit) async {
  if (processExit != null) {
    try {
      await processExit.timeout(const Duration(seconds: 6));
    } catch (_) {}
  }
}
