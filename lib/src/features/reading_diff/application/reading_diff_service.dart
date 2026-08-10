import 'dart:convert';

import 'package:alera/src/features/ai_text_generation/application/ai_text_agent_runner.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_errors.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_registry.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/features/reading_diff/application/reading_diff_cache.dart';
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
    final agent = request.settings.agentFor(operation);
    final spec = aiTextAgentSpecs[agent];
    if (spec == null ||
        !spec.supportsStructuredOutput ||
        !spec.supportsRepositoryRead ||
        !spec.supportsLargePrompt ||
        !spec.readOnlyGuarantee) {
      throw AiTextGenerationException(
        '${agent.label} cannot generate a structured reading diff with read-only repository access. Choose Codex or Claude Code.',
      );
    }
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
      area: request.area,
      commitOid: request.commitOid,
      parentOid: request.parentOid,
      baseRef: request.baseRef,
    );
    if (rawDiff.isEmpty) {
      throw const AiTextGenerationException('No diff is available to read.');
    }
    final rust.ReadingDiffPreparation compiler;
    try {
      compiler = await rust.prepareReadingDiff(diff: rawDiff);
    } on rust.ReadingDiffError catch (error) {
      throw AiTextGenerationException(error.message);
    }
    final instructions = request.settings.instructionsFor(operation);
    final cacheKey = sha256.convert(<int>[
      ...utf8.encode(compiler.rubricVersion),
      ...utf8.encode('|${compiler.schemaVersion}|${agent.key}|${model.id}|'),
      ...utf8.encode(effort ?? ''),
      ...utf8.encode('|$instructions|'),
      ...rawDiff,
    ]).toString();
    return ReadingDiffPreparation(
      request: request,
      rawDiff: rawDiff,
      compiler: compiler,
      agent: agent,
      model: model.id,
      effort: effort,
      accessPolicy: AgentTaskAccessPolicy.repositoryReadOnly,
      cacheKey: cacheKey,
      cachedResult: request.ignoreCache ? null : await cache.read(cacheKey),
    );
  }

  Future<ReadingDiffResult> generate(ReadingDiffPreparation preparation) async {
    final cached = preparation.cachedResult;
    if (cached != null) {
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
    var agentLabel = preparation.agent.label;
    try {
      for (final chunk in preparation.compiler.chunks) {
        _throwIfCanceled(lane);
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
            planJson: plan.text,
          );
        } on rust.ReadingDiffError catch (error) {
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
              planJson: plan.text,
            );
          } on rust.ReadingDiffError catch (repairError) {
            throw AiTextGenerationException(
              'The replacement reading diff plan was invalid: ${repairError.message}',
            );
          }
        }
        agentLabel = plan.agentLabel;
        compiled.add(
          rust.ReadingDiffCompiledChunk(
            index: chunk.index,
            readingDiff: result.readingDiff,
            summary: result.summary,
            changedLines: result.changedLines,
            retainedChangedLines: result.retainedChangedLines,
          ),
        );
      }
      _throwIfCanceled(lane);
      final merged = await rust.mergeReadingDiffChunks(chunks: compiled);
      final result = ReadingDiffResult(
        diff: merged.readingDiff,
        summary: merged.summary,
        changedLines: merged.changedLines,
        retainedChangedLines: merged.retainedChangedLines,
        agentLabel: agentLabel,
      );
      await cache.write(preparation.cacheKey, result);
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

  String _lane(ReadingDiffRequest request) =>
      '${request.workspacePath}::${request.filePath ?? '*'}::${request.area?.key ?? 'all'}::${request.commitOid ?? request.baseRef ?? 'worktree'}';
}
