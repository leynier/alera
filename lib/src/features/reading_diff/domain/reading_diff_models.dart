import 'dart:typed_data';

import 'package:alera/src/features/ai_assist/application/ai_assist_agent_runner.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/rust/api/reading_diff.dart' as rust;
import 'package:alera/src/shared/infra/git/git_diff_models.dart';

class const ReadingDiffRequest({
  required final String workspacePath,
  required final AiAssistSettings settings,
  final String? filePath,
  final String? oldPath,
  final GitChangeArea? area,
  final String? commitOid,
  final String? parentOid,
  final String? baseRef,
  final bool ignoreCache = false,
});

class const ReadingDiffPreparation({
  required final ReadingDiffRequest request,
  required final Uint8List rawDiff,
  required final rust.ReadingDiffPreparation compiler,
  required final AiAssistAgent agent,
  required final String model,
  required final String? effort,
  required final AgentTaskAccessPolicy accessPolicy,
  required final String cacheKey,
  final ReadingDiffResult? cachedResult,
}) {
  int get rawBytes => compiler.rawBytes.toInt();
  int get chunkCount => compiler.chunks.length;
}

class const ReadingDiffResult({
  required final Uint8List diff,
  required final String summary,
  required final int changedLines,
  required final int retainedChangedLines,
  required final String agentLabel,
  final String? model,
  final String? effort,
  final List<ReadingDiffChunkSummary> chunkSummaries =
      const <ReadingDiffChunkSummary>[],
  final bool fromCache = false,
}) {
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

class const ReadingDiffChunkSummary({
  required final int index,
  required final String summary,
});
