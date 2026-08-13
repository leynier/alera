import 'dart:convert';
import 'dart:isolate';

import 'package:alera/src/features/ai_text_generation/application/ai_text_agent_runner.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_diff_only_execution.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_errors.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_registry.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/features/reading_diff/application/reading_diff_cache.dart';
import 'package:alera/src/features/reading_diff/application/reading_diff_generation_progress.dart';
import 'package:alera/src/features/reading_diff/application/reading_diff_prompt.dart';
import 'package:alera/src/features/reading_diff/domain/reading_diff_models.dart';
import 'package:alera/src/rust/api/reading_diff.dart' as rust;
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:crypto/crypto.dart';

class ReadingDiffService {
  ReadingDiffService({
    required this.gitBackend,
    required this.runner,
    ReadingDiffCache? cache,
  }) : cache = cache ?? const FileReadingDiffCache();

  final GitBackend gitBackend;
  final AgentTaskRunner runner;
  final ReadingDiffCache cache;
  final Set<String> _pending = <String>{};
  final Map<String, String> _activeRunByLane = <String, String>{};
  final Set<String> _canceled = <String>{};

  Future<ReadingDiffPreparation> prepare(ReadingDiffRequest request) async {
    if (!request.settings.enabled) {
      throw const AiTextGenerationException('AI text generation is disabled.');
    }
    final operation = AiTextGenerationOperation.readingDiff;
    final agent = readingDiffAgentForSettings(request.settings);
    final spec = aiTextAgentSpecs[agent];
    if (spec == null && agent != AiTextGenerationAgent.custom) {
      throw AiTextGenerationException(
        '${agent.label} does not support AI text generation.',
      );
    }
    requireDiffOnlyAiTextAgent(agent);
    final model = modelForAgent(
      agent,
      request.settings.modelForOperation(operation) ??
          defaultModelIdForAgent(agent, request.settings),
      extraModels: discoveredModelsForAgent(request.settings, agent),
    );
    final effort = request.settings.thinkingForOperation(operation, model.id);
    final rawDiff = await gitBackend.readingDiffPatch(
      path: request.workspacePath,
      filePath: request.filePath,
      oldPath: request.oldPath,
      area: request.area,
      commitOid: request.commitOid,
      parentOid: request.parentOid,
      baseRef: request.baseRef,
    );
    if (rawDiff.isEmpty) {
      throw const AiTextGenerationException('No diff is available to read.');
    }
    final promptLimit = _promptLimit(agent, request.settings, spec);
    final chunkLimit = _chunkLimit(promptLimit);
    final rust.ReadingDiffPreparation compiler;
    try {
      compiler = await rust.prepareReadingDiff(
        diff: rawDiff,
        maxChunkBytes: BigInt.from(chunkLimit),
      );
    } on rust.ReadingDiffError catch (error) {
      throw AiTextGenerationException(error.message);
    }
    final instructions = request.settings.instructionsFor(operation);
    final oversizedChunk = await firstOversizedReadingDiffPromptChunk(
      preparation: compiler,
      customInstructions: instructions,
      maxBytes: promptLimit,
    );
    if (oversizedChunk != null) {
      throw AiTextGenerationException(
        '${agent.label} cannot receive diff chunk ${oversizedChunk + 1} within its safe prompt limit.',
      );
    }
    final cacheKey = await buildReadingDiffCacheKey(
      rubricVersion: compiler.rubricVersion,
      schemaVersion: compiler.schemaVersion,
      agent: agent,
      model: model.id,
      effort: effort,
      instructions: instructions,
      customCommand: request.settings.customCommand,
      rawDiff: rawDiff,
    );
    return ReadingDiffPreparation(
      request: request,
      rawDiff: rawDiff,
      compiler: compiler,
      agent: agent,
      model: model.id,
      effort: effort,
      accessPolicy: AgentTaskAccessPolicy.diffOnly,
      cacheKey: cacheKey,
      cachedResult: request.ignoreCache ? null : await cache.read(cacheKey),
    );
  }

  Future<ReadingDiffResult> generate(
    ReadingDiffPreparation preparation, {
    void Function(ReadingDiffGenerationProgress progress)? onProgress,
  }) async {
    final cached = preparation.cachedResult;
    if (cached != null) {
      onProgress?.call(
        ReadingDiffGenerationProgress(
          stage: ReadingDiffGenerationStage.cached,
          completedChunks: preparation.chunkCount,
          totalChunks: preparation.chunkCount,
        ),
      );
      return cached;
    }
    final lane = _lane(preparation.request);
    if (_pending.contains(lane)) {
      throw const AiTextGenerationException(
        'Reading diff generation is already running.',
      );
    }
    _pending.add(lane);
    _canceled.remove(lane);
    final compiled = <rust.ReadingDiffCompiledChunk>[];
    final chunkSummaries = <ReadingDiffChunkSummary>[];
    var agentLabel = preparation.agent.label;
    try {
      for (final chunk in preparation.compiler.chunks) {
        _throwIfCanceled(lane);
        onProgress?.call(
          ReadingDiffGenerationProgress(
            stage: ReadingDiffGenerationStage.generating,
            completedChunks: compiled.length,
            totalChunks: preparation.chunkCount,
            currentChunk: chunk.index + 1,
          ),
        );
        final prompt = buildReadingDiffPrompt(
          preparation: preparation.compiler,
          chunk: chunk,
          customInstructions: preparation.request.settings.instructionsFor(
            AiTextGenerationOperation.readingDiff,
          ),
        );
        var plan = await _runPlan(preparation, lane, chunk.index, prompt);
        rust.ReadingDiffCompileResult result;
        try {
          result = await rust.compileReadingDiffPlan(
            diff: chunk.rawDiff,
            sourceDiff: preparation.rawDiff,
            planJson: plan.text,
          );
        } on rust.ReadingDiffError catch (error) {
          onProgress?.call(
            ReadingDiffGenerationProgress(
              stage: ReadingDiffGenerationStage.repairing,
              completedChunks: compiled.length,
              totalChunks: preparation.chunkCount,
              currentChunk: chunk.index + 1,
            ),
          );
          final repairPrompt = buildReadingDiffRepairPrompt(
            originalPrompt: prompt,
            rejectedPlan: plan.text,
            compilerError: error.message,
          );
          plan = await _runPlan(
            preparation,
            lane,
            chunk.index,
            repairPrompt,
            repair: true,
          );
          try {
            result = await rust.compileReadingDiffPlan(
              diff: chunk.rawDiff,
              sourceDiff: preparation.rawDiff,
              planJson: plan.text,
            );
          } on rust.ReadingDiffError catch (repairError) {
            throw AiTextGenerationException(
              'The replacement reading diff plan was invalid: ${repairError.message}',
            );
          }
        }
        agentLabel = plan.agentLabel;
        chunkSummaries.add(
          ReadingDiffChunkSummary(
            index: chunk.index.toInt(),
            summary: result.summary,
          ),
        );
        compiled.add(
          rust.ReadingDiffCompiledChunk(
            index: chunk.index,
            continuationPreamble: chunk.continuationPreamble,
            readingDiff: result.readingDiff,
            summary: result.summary,
            changedLines: result.changedLines,
            retainedChangedLines: result.retainedChangedLines,
          ),
        );
      }
      _throwIfCanceled(lane);
      onProgress?.call(
        ReadingDiffGenerationProgress(
          stage: ReadingDiffGenerationStage.combining,
          completedChunks: preparation.chunkCount,
          totalChunks: preparation.chunkCount,
        ),
      );
      final merged = await rust.mergeReadingDiffChunks(
        chunks: compiled,
        sourceDiff: preparation.rawDiff,
      );
      _throwIfCanceled(lane);
      final result = ReadingDiffResult(
        diff: merged.readingDiff,
        summary: merged.summary,
        changedLines: merged.changedLines,
        retainedChangedLines: merged.retainedChangedLines,
        agentLabel: agentLabel,
        model: preparation.model,
        effort: preparation.effort,
        chunkSummaries: chunkSummaries,
      );
      await cache.writeBestEffort(preparation.cacheKey, result);
      if (_canceled.contains(lane)) {
        await cache.removeBestEffort(preparation.cacheKey);
        _throwIfCanceled(lane);
      }
      return result;
    } finally {
      _pending.remove(lane);
      _activeRunByLane.remove(lane);
      _canceled.remove(lane);
    }
  }

  void cancel(ReadingDiffRequest request) {
    final lane = _lane(request);
    _canceled.add(lane);
    final runId = _activeRunByLane[lane];
    if (runId != null) {
      runner.cancel(runId);
    }
  }

  Future<AiTextAgentRunResult> _runPlan(
    ReadingDiffPreparation preparation,
    String lane,
    int chunkIndex,
    String prompt, {
    bool repair = false,
  }) async {
    _throwIfCanceled(lane);
    final runId = '$lane::chunk-$chunkIndex${repair ? '-repair' : ''}';
    _activeRunByLane[lane] = runId;
    final result = await runner.run(
      AiTextAgentRunRequest(
        settings: preparation.request.settings,
        prompt: prompt,
        runId: runId,
        workingDirectory: preparation.request.workspacePath,
        agent: preparation.agent,
        model: preparation.model,
        reasoning: preparation.effort,
        accessPolicy: preparation.accessPolicy,
        outputContract: AgentTaskOutputContract.readingDiffPlanV1,
        outputSchema: preparation.compiler.planSchema,
      ),
    );
    _activeRunByLane.remove(lane);
    return result;
  }

  void _throwIfCanceled(String lane) {
    if (_canceled.contains(lane)) {
      throw const AiTextGenerationCanceledException();
    }
  }

  String _lane(ReadingDiffRequest request) => jsonEncode(<String?>[
    request.workspacePath,
    request.filePath,
    request.oldPath,
    request.area?.key,
    request.commitOid,
    request.parentOid,
    request.baseRef,
  ]);
}

const int _defaultReadingDiffChunkBytes = 160 * 1024;
const int _argvPromptBytes = 24000;

int _promptLimit(
  AiTextGenerationAgent agent,
  AiTextGenerationSettings settings,
  AiTextAgentSpec? spec,
) {
  if (agent == AiTextGenerationAgent.custom) {
    return settings.customCommand.contains('{prompt}')
        ? _argvPromptBytes
        : 1024 * 1024;
  }
  return spec?.maxPromptBytes ?? _argvPromptBytes;
}

int _chunkLimit(int promptLimit) {
  final conservativeLimit = (promptLimit - 8192) ~/ 4;
  return conservativeLimit.clamp(4096, _defaultReadingDiffChunkBytes);
}

Future<String> buildReadingDiffCacheKey({
  required String rubricVersion,
  required int schemaVersion,
  required AiTextGenerationAgent agent,
  required String model,
  required String? effort,
  required String instructions,
  required String customCommand,
  required List<int> rawDiff,
}) {
  final identity = jsonEncode(<String, Object?>{
    'rubricVersion': rubricVersion,
    'schemaVersion': schemaVersion,
    'agent': agent.key,
    'model': model,
    'effort': effort,
    'instructions': instructions,
    'customCommand': agent == AiTextGenerationAgent.custom
        ? customCommand.trim()
        : null,
  });
  return Isolate.run(() => _hashReadingDiffCacheKey(identity, rawDiff));
}

String _hashReadingDiffCacheKey(String identity, List<int> rawDiff) =>
    sha256.convert(<int>[...utf8.encode(identity), 0, ...rawDiff]).toString();
