import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/ai_assist/application/ai_assist_diff_only_execution.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_errors.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_host_completer.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_prompt.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_registry.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_process_failure.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;

part 'ai_assist_agent_command_plan.dart';

enum AgentTaskAccessPolicy { repositoryReadOnly, diffOnly }

enum AgentTaskOutputContract { plainText, readingDiffPlanV1 }

/// Agent CLIs are user-configurable processes, so their output must not be
/// allowed to grow without a bound while the desktop waits for completion.
const int aiAssistAgentMaxOutputBytes = 4 * 1024 * 1024;

class const AiAssistAgentRunRequest({
  required final AiAssistSettings settings,
  required final String prompt,
  required final String runId,
  required final String? workingDirectory,
  final AiAssistAgent? agent,
  final AiAssistOperation? operation,
  final String? model,
  final String? reasoning,
  final String Function(String) cleanOutput = cleanGeneratedText,
  final AgentTaskAccessPolicy accessPolicy =
      AgentTaskAccessPolicy.repositoryReadOnly,
  final AgentTaskOutputContract outputContract =
      AgentTaskOutputContract.plainText,
  final String? outputSchema,
});

class const AiAssistAgentRunResult({
  required final String text,
  required final String agentLabel,
});

abstract interface class AgentTaskRunner {
  Future<AiAssistAgentRunResult> run(AiAssistAgentRunRequest request);

  void cancel(String runId);
}

abstract interface class AiAssistAgentRunner implements AgentTaskRunner {}

class CliAiAssistAgentRunner({
  required final ProcessRunner processRunner,
  CommandEnvironmentResolver? commandEnvironmentResolver,
  this.hostCompleter,
  this.chatGptCompleter,
}) implements AiAssistAgentRunner {
  this
    : commandEnvironmentResolver =
          commandEnvironmentResolver ?? UserCommandEnvironmentResolver();

  final CommandEnvironmentResolver commandEnvironmentResolver;
  final AiAssistHostCompleter? hostCompleter;
  final AiAssistHostCompleter? chatGptCompleter;
  final Map<String, StartedProcess> _running = <String, StartedProcess>{};
  final Set<String> _pending = <String>{};
  final Set<String> _canceled = <String>{};
  final Map<String, AiAssistHostCompleter> _hostRuns =
      <String, AiAssistHostCompleter>{};

  @override
  Future<AiAssistAgentRunResult> run(AiAssistAgentRunRequest request) async {
    if (_pending.contains(request.runId) ||
        _running.containsKey(request.runId) ||
        _hostRuns.containsKey(request.runId)) {
      throw const AiAssistException('Generation is already running.');
    }
    _canceled.remove(request.runId);
    _pending.add(request.runId);

    final requestedAgent = request.agent ?? request.settings.agent;
    if (requestedAgent == AiAssistAgent.opencodeGo ||
        requestedAgent == AiAssistAgent.chatgpt) {
      return _runDirectProvider(request, requestedAgent);
    }

    _AiAssistAgentCommandPlan? plan;
    Directory? isolatedDirectory;
    Future<int>? processExit;
    try {
      var environment = await commandEnvironmentResolver.environment();
      if (request.accessPolicy == AgentTaskAccessPolicy.diffOnly &&
          requestedAgent == AiAssistAgent.codex) {
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
        throw const AiAssistCanceledException();
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
        throw AiAssistException(
          '${plan.label} could not be started. Check that ${plan.binary} is installed and on PATH.',
        );
      }
      processExit = process.exitCode;
      if (_canceled.contains(request.runId)) {
        process.kill();
        throw const AiAssistCanceledException();
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
          throw AiAssistException(
            'Generation timed out after ${request.settings.timeoutSeconds}s.',
          );
        },
      );
      if (_canceled.contains(request.runId)) {
        throw const AiAssistCanceledException();
      }
      if (output.exitCode != 0) {
        final detail = aiAssistProcessFailureDetail(
          output.stdout,
          output.stderr,
        );
        throw AiAssistException(
          detail == null
              ? '${plan.label} failed. Check the agent CLI configuration and try again.'
              : '${plan.label} failed: $detail',
        );
      }
      final rawOutput = plan.outputFile == null
          ? output.stdout
          : await _readBoundedOutputFile(plan.outputFile!);
      final text = request.outputContract == AgentTaskOutputContract.plainText
          ? request.cleanOutput(rawOutput)
          : _cleanStructuredOutput(request.cleanOutput(rawOutput));
      if (text.trim().isEmpty) {
        throw AiAssistException('${plan.label} returned no text.');
      }
      return AiAssistAgentRunResult(text: text, agentLabel: plan.label);
    } on _AiAssistAgentOutputLimitException {
      throw AiAssistException(
        '${plan?.label ?? 'Agent'} returned too much output.',
      );
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

  Future<AiAssistAgentRunResult> _runDirectProvider(
    AiAssistAgentRunRequest request,
    AiAssistAgent agent,
  ) async {
    try {
      if (request.accessPolicy == AgentTaskAccessPolicy.diffOnly) {
        requireDiffOnlyAiAssistAgent(agent);
      }
      final completer = agent == AiAssistAgent.chatgpt
          ? chatGptCompleter
          : hostCompleter;
      if (completer == null) {
        throw AiAssistException(
          'The running terminal host does not support ${agent.label} AI Assist.',
        );
      }
      if (_canceled.contains(request.runId)) {
        throw const AiAssistCanceledException();
      }
      _pending.remove(request.runId);
      _hostRuns[request.runId] = completer;
      final model = modelForAgent(
        agent,
        request.model ??
            request.settings.modelFor(agent) ??
            defaultModelIdForAgent(agent, request.settings),
        extraModels: discoveredModelsForAgent(request.settings, agent),
      );
      final operation = request.operation;
      final selectedThinkingByModel = request.settings.selectedThinkingByModel;
      final selectedThinkingByOperation = operation == null
          ? const <String, String>{}
          : request.settings.selectedThinkingByOperation[operation] ??
                const <String, String>{};
      final hasSavedThinking =
          selectedThinkingByModel.isNotEmpty ||
          selectedThinkingByOperation.isNotEmpty;
      final thinkingContext =
          agent == AiAssistAgent.chatgpt &&
              model.id.trim().isEmpty &&
              hasSavedThinking
          ? AiAssistThinkingContext(
              operation: operation,
              selectedThinkingByModel: selectedThinkingByModel,
              selectedThinkingByOperation: selectedThinkingByOperation,
            )
          : null;
      final result = await completer.complete(
        prompt: request.prompt,
        model: model.id,
        sessionId: request.runId,
        operationId: request.runId,
        timeoutSeconds: request.settings.timeoutSeconds,
        thinkingLevel: agent == AiAssistAgent.chatgpt
            ? request.reasoning ?? request.settings.thinkingForModel(model.id)
            : null,
        serviceTier: agent == AiAssistAgent.chatgpt
            ? request.settings.effectiveChatGptServiceTier
            : null,
        thinkingContext: thinkingContext,
      );
      if (_canceled.contains(request.runId)) {
        throw const AiAssistCanceledException();
      }
      final text = request.outputContract == AgentTaskOutputContract.plainText
          ? request.cleanOutput(result.text)
          : _cleanStructuredOutput(request.cleanOutput(result.text));
      if (text.trim().isEmpty) {
        throw AiAssistException('${agent.label} returned no text.');
      }
      return AiAssistAgentRunResult(text: text, agentLabel: result.agentLabel);
    } finally {
      _pending.remove(request.runId);
      _hostRuns.remove(request.runId);
      _canceled.remove(request.runId);
    }
  }

  @override
  void cancel(String runId) {
    if (!_pending.contains(runId) &&
        !_running.containsKey(runId) &&
        !_hostRuns.containsKey(runId)) {
      return;
    }
    _canceled.add(runId);
    _running[runId]?.kill();
    if (_hostRuns.containsKey(runId)) {
      final completer = _hostRuns[runId];
      if (completer != null) {
        unawaited(completer.cancel(runId));
      }
    }
  }

  Future<ProcessRunOutput> _collectProcess(StartedProcess process) async {
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final collector = _AiAssistProcessOutputCollector(
      maxBytes: aiAssistAgentMaxOutputBytes,
    );
    try {
      final stdoutDone = collector.collect(process.stdout, stdout);
      final stderrDone = collector.collect(process.stderr, stderr);
      var exitCode = 0;
      final exitDone = process.exitCode.then<void>((value) {
        exitCode = value;
      });
      await Future.wait<void>(<Future<void>>[
        stdoutDone,
        stderrDone,
        exitDone,
      ], eagerError: true);
      return ProcessRunOutput(
        exitCode: exitCode,
        stdout: stdout.toString(),
        stderr: stderr.toString(),
      );
    } catch (error, stackTrace) {
      // A decoder or stream error stops one reader before the child exits. Kill
      // the process tree first, cancel the sibling reader, and reap the child
      // before returning the original error to the caller.
      _killProcess(process);
      await collector.cancel();
      await _waitForProcessExit(process.exitCode);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<String> _readBoundedOutputFile(File file) async {
    final bytes = await file
        .openRead(0, aiAssistAgentMaxOutputBytes + 1)
        .fold<List<int>>(<int>[], (buffer, chunk) {
          buffer.addAll(chunk);
          return buffer;
        });
    if (bytes.length > aiAssistAgentMaxOutputBytes) {
      throw const _AiAssistAgentOutputLimitException();
    }
    return utf8.decode(bytes, allowMalformed: true);
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

class const _AiAssistAgentOutputLimitException() implements Exception;

class _AiAssistProcessOutputCollector {
  _AiAssistProcessOutputCollector({required this.maxBytes});

  final int maxBytes;
  var _totalBytes = 0;
  final List<StreamSubscription<String>> _subscriptions =
      <StreamSubscription<String>>[];
  final List<Completer<void>> _completers = <Completer<void>>[];

  Future<void> collect(Stream<List<int>> stream, StringBuffer buffer) {
    final completer = Completer<void>();
    final counted = stream.map((chunk) {
      _totalBytes += chunk.length;
      if (_totalBytes > maxBytes) {
        throw const _AiAssistAgentOutputLimitException();
      }
      return chunk;
    });
    final decoded = utf8.decoder.bind(counted);
    final subscription = decoded.listen(
      buffer.write,
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      cancelOnError: true,
    );
    _subscriptions.add(subscription);
    _completers.add(completer);
    return completer.future;
  }

  Future<void> cancel() async {
    await Future.wait<void>(<Future<void>>[
      for (final subscription in _subscriptions)
        _cancelSubscription(subscription),
    ], eagerError: false);
    for (final completer in _completers) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    await Future.wait<void>(<Future<void>>[
      for (final completer in _completers) _ignoreOutputError(completer.future),
    ], eagerError: false);
  }
}

Future<void> _cancelSubscription(
  StreamSubscription<String> subscription,
) async {
  try {
    await subscription.cancel().timeout(const Duration(seconds: 1));
  } on Object {
    // The process has already been terminated; a broken stream cancellation
    // must not hide the original output error or keep the runner waiting.
  }
}

Future<void> _ignoreOutputError(Future<void> future) async {
  try {
    await future;
  } on Object {
    // The first output error is rethrown by _collectProcess.
  }
}

void _killProcess(StartedProcess process) {
  try {
    process.kill();
  } on Object {
    // Preserve the output or stream failure that caused the termination.
  }
}

Future<void> _waitForProcessExit(Future<int>? processExit) async {
  if (processExit != null) {
    try {
      await processExit.timeout(const Duration(seconds: 6));
    } catch (_) {}
  }
}
