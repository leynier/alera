import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_errors.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_prompt.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_registry.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;

const int maxArgvPromptBytes = 24000;

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
  });

  final AiTextGenerationSettings settings;
  final String prompt;
  final String runId;
  final String? workingDirectory;
  final AiTextGenerationAgent? agent;
  final String? model;
  final String? reasoning;
  final String Function(String) cleanOutput;
}

class AiTextAgentRunResult {
  const AiTextAgentRunResult({required this.text, required this.agentLabel});

  final String text;
  final String agentLabel;
}

abstract interface class AiTextAgentRunner {
  Future<AiTextAgentRunResult> run(AiTextAgentRunRequest request);

  void cancel(String runId);
}

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
    try {
      final environment = await commandEnvironmentResolver.environment();
      plan = await _planCommand(request, environment);
      if (_canceled.contains(request.runId)) {
        throw const AiTextGenerationCanceledException();
      }
      final StartedProcess process;
      try {
        process = await processRunner.start(
          plan.binary,
          plan.args,
          workingDirectory: request.workingDirectory,
          environment: <String, String>{
            ...environment,
            ...plan.environmentOverrides,
          },
        );
      } catch (_) {
        throw AiTextGenerationException(
          '${plan.label} could not be started. Check that ${plan.binary} is installed and on PATH.',
        );
      }
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
        final detail = _failureDetail(output.stdout, output.stderr);
        throw AiTextGenerationException(
          detail == null
              ? '${plan.label} failed. Check the agent CLI configuration and try again.'
              : '${plan.label} failed: $detail',
        );
      }
      final text = request.cleanOutput(output.stdout);
      if (text.trim().isEmpty) {
        throw AiTextGenerationException('${plan.label} returned no text.');
      }
      return AiTextAgentRunResult(text: text, agentLabel: plan.label);
    } finally {
      _pending.remove(request.runId);
      _running.remove(request.runId);
      _canceled.remove(request.runId);
      await plan?.dispose();
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

  Future<_AiTextAgentCommandPlan> _planCommand(
    AiTextAgentRunRequest request,
    Map<String, String> environment,
  ) async {
    final settings = request.settings;
    final agent = request.agent ?? settings.agent;
    if (agent == AiTextGenerationAgent.custom) {
      return _planCustomCommand(settings.customCommand, request.prompt);
    }
    final spec = aiTextAgentSpecs[agent];
    if (spec == null) {
      throw AiTextGenerationException(
        '${agent.label} does not support AI text generation.',
      );
    }
    final model = modelForAgent(
      agent,
      request.model ??
          settings.modelFor(agent) ??
          defaultModelIdForAgent(agent, settings),
      extraModels: discoveredModelsForAgent(settings, agent),
    );
    final thinking =
        request.reasoning ??
        settings.thinkingForModel(model.id) ??
        model.defaultThinkingLevel;
    if (spec.promptDelivery == AiPromptDelivery.argv &&
        utf8.encode(request.prompt).length > maxArgvPromptBytes) {
      throw AiTextGenerationException(
        '${spec.label} cannot receive large prompts safely. Choose an agent that supports stdin prompts or reduce the staged diff.',
      );
    }
    Directory? promptDirectory;
    final environmentOverrides = <String, String>{};
    var deliveredPrompt = '';
    if (spec.promptDelivery == AiPromptDelivery.argv) {
      deliveredPrompt = request.prompt;
    } else if (spec.promptDelivery == AiPromptDelivery.promptFile) {
      promptDirectory = await Directory.systemTemp.createTemp('alera-ai-text-');
      try {
        final promptFile = File(
          '${promptDirectory.path}${Platform.pathSeparator}prompt.txt',
        );
        await promptFile.writeAsString(request.prompt, flush: true);
        deliveredPrompt = promptFile.path;
        if (agent == AiTextGenerationAgent.grok) {
          final grokHome = Directory(p.join(promptDirectory.path, 'grok-home'));
          await grokHome.create();
          await _copyGrokRuntimeConfiguration(grokHome, environment);
          environmentOverrides['GROK_HOME'] = grokHome.path;
        }
      } catch (_) {
        try {
          await promptDirectory.delete(recursive: true);
        } catch (_) {}
        rethrow;
      }
    }
    return _AiTextAgentCommandPlan(
      binary: spec.binary,
      args: spec.buildArgs(
        prompt: deliveredPrompt,
        model: model.id,
        thinkingLevel: thinking,
        timeoutSeconds: settings.timeoutSeconds,
      ),
      stdinPayload: spec.promptDelivery == AiPromptDelivery.stdin
          ? request.prompt
          : null,
      label: spec.label,
      promptDirectory: promptDirectory,
      environmentOverrides: environmentOverrides,
    );
  }

  Future<void> _copyGrokRuntimeConfiguration(
    Directory isolatedHome,
    Map<String, String> environment,
  ) async {
    final configuredHome = environment['GROK_HOME']?.trim();
    final userHome = (environment['HOME'] ?? environment['USERPROFILE'])
        ?.trim();
    final sourceHome = configuredHome != null && configuredHome.isNotEmpty
        ? configuredHome
        : userHome != null && userHome.isNotEmpty
        ? p.join(userHome, '.grok')
        : null;
    if (sourceHome == null) {
      return;
    }
    for (final fileName in const <String>[
      'auth.json',
      'config.toml',
      'managed_config.toml',
      'requirements.toml',
    ]) {
      final source = File(p.join(sourceHome, fileName));
      if (await source.exists()) {
        await source.copy(p.join(isolatedHome.path, fileName));
      }
    }
  }

  _AiTextAgentCommandPlan _planCustomCommand(String template, String prompt) {
    final tokens = _tokenizeCommandTemplate(template);
    if (tokens.isEmpty) {
      throw const AiTextGenerationException('Custom command is empty.');
    }
    final usesPlaceholder = tokens.any((token) => token.contains('{prompt}'));
    final substituted = tokens
        .map((token) => token.replaceAll('{prompt}', prompt))
        .toList(growable: false);
    return _AiTextAgentCommandPlan(
      binary: substituted.first,
      args: substituted.skip(1).toList(growable: false),
      stdinPayload: usesPlaceholder ? null : prompt,
      label: substituted.first,
    );
  }

  List<String> _tokenizeCommandTemplate(String template) {
    final matches = RegExp(
      r'''"([^"]*)"|'([^']*)'|(\S+)''',
    ).allMatches(template);
    return matches
        .map((match) => match.group(1) ?? match.group(2) ?? match.group(3)!)
        .toList(growable: false);
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

class _AiTextAgentCommandPlan {
  const _AiTextAgentCommandPlan({
    required this.binary,
    required this.args,
    required this.stdinPayload,
    required this.label,
    this.environmentOverrides = const <String, String>{},
    this.promptDirectory,
  });

  final String binary;
  final List<String> args;
  final String? stdinPayload;
  final String label;
  final Map<String, String> environmentOverrides;
  final Directory? promptDirectory;

  Future<void> dispose() async {
    final directory = promptDirectory;
    if (directory == null) {
      return;
    }
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}
  }
}
