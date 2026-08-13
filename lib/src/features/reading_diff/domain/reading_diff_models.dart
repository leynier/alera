import 'dart:typed_data';

import 'package:alera/src/features/ai_text_generation/application/ai_text_agent_runner.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/rust/api/reading_diff.dart' as rust;
import 'package:alera/src/shared/infra/git/git_diff_models.dart';

class ReadingDiffRequest {
  const ReadingDiffRequest({
    required this.workspacePath,
    required this.settings,
    this.filePath,
    this.area,
    this.commitOid,
    this.parentOid,
    this.baseRef,
    this.ignoreCache = false,
  });

  final String workspacePath;
  final AiTextGenerationSettings settings;
  final String? filePath;
  final GitChangeArea? area;
  final String? commitOid;
  final String? parentOid;
  final String? baseRef;
  final bool ignoreCache;
}

class ReadingDiffPreparation {
  const ReadingDiffPreparation({
    required this.request,
    required this.rawDiff,
    required this.compiler,
    required this.agent,
    required this.model,
    required this.effort,
    required this.accessPolicy,
    required this.cacheKey,
    this.cachedResult,
  });

  final ReadingDiffRequest request;
  final Uint8List rawDiff;
  final rust.ReadingDiffPreparation compiler;
  final AiTextGenerationAgent agent;
  final String model;
  final String? effort;
  final AgentTaskAccessPolicy accessPolicy;
  final String cacheKey;
  final ReadingDiffResult? cachedResult;

  int get rawBytes => compiler.rawBytes.toInt();
  int get chunkCount => compiler.chunks.length;
}

class ReadingDiffResult {
  const ReadingDiffResult({
    required this.diff,
    required this.summary,
    required this.changedLines,
    required this.retainedChangedLines,
    required this.agentLabel,
    this.model,
    this.effort,
    this.chunkSummaries = const <ReadingDiffChunkSummary>[],
    this.fromCache = false,
  });

  final Uint8List diff;
  final String summary;
  final int changedLines;
  final int retainedChangedLines;
  final String agentLabel;
  final String? model;
  final String? effort;
  final List<ReadingDiffChunkSummary> chunkSummaries;
  final bool fromCache;

  int? get chunkCount => chunkSummaries.isEmpty ? null : chunkSummaries.length;

  double get retainedFraction =>
      changedLines == 0 ? 1 : retainedChangedLines / changedLines;

  ReadingDiffResult asCached() => ReadingDiffResult(
    diff: diff,
    summary: summary,
    changedLines: changedLines,
    retainedChangedLines: retainedChangedLines,
    agentLabel: agentLabel,
    model: model,
    effort: effort,
    chunkSummaries: chunkSummaries,
    fromCache: true,
  );
}

class ReadingDiffChunkSummary {
  const ReadingDiffChunkSummary({required this.index, required this.summary});

  final int index;
  final String summary;
}
