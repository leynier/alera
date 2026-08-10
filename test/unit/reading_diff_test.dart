import 'dart:io';
import 'dart:typed_data';

import 'package:alera/src/features/ai_text_generation/application/ai_text_agent_runner.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/features/reading_diff/application/reading_diff_cache.dart';
import 'package:alera/src/features/reading_diff/application/reading_diff_generation_progress.dart';
import 'package:alera/src/features/reading_diff/application/reading_diff_prompt.dart';
import 'package:alera/src/features/reading_diff/domain/reading_diff_models.dart';
import 'package:alera/src/rust/api/reading_diff.dart' as rust;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reading diff models expose preparation and cached result state', () {
    final compiler = rust.ReadingDiffPreparation(
      rawBytes: BigInt.from(42),
      schemaVersion: 1,
      rubricVersion: 'reading-diff-rubric-v1',
      planSchema: '{}',
      chunks: <rust.ReadingDiffChunk>[
        rust.ReadingDiffChunk(
          index: 0,
          rawDiff: Uint8List.fromList(<int>[1]),
          numberedDiff: '1|diff --git a/a b/a',
        ),
      ],
    );
    final request = ReadingDiffRequest(
      workspacePath: '/repo',
      settings: AiTextGenerationSettings.defaults,
      baseRef: 'main',
      ignoreCache: true,
    );
    final preparation = ReadingDiffPreparation(
      request: request,
      rawDiff: Uint8List.fromList(<int>[1]),
      compiler: compiler,
      agent: AiTextGenerationAgent.agy,
      model: 'agent-model',
      effort: 'medium',
      accessPolicy: AgentTaskAccessPolicy.diffOnly,
      cacheKey: 'key',
    );
    expect(preparation.rawBytes, 42);
    expect(preparation.chunkCount, 1);
    expect(request.baseRef, 'main');
    expect(request.ignoreCache, isTrue);

    final result = ReadingDiffResult(
      diff: Uint8List.fromList(<int>[1, 2]),
      summary: 'Focus the behavioral change.',
      changedLines: 4,
      retainedChangedLines: 1,
      agentLabel: 'Codex',
    );
    expect(result.retainedFraction, 0.25);
    expect(result.asCached().fromCache, isTrue);
    expect(
      ReadingDiffResult(
        diff: Uint8List(0),
        summary: 'No changes.',
        changedLines: 0,
        retainedChangedLines: 0,
        agentLabel: 'Codex',
      ).retainedFraction,
      1,
    );
  });

  test('reading diff progress reports lifecycle labels and fractions', () {
    const preparing = ReadingDiffGenerationProgress(
      stage: ReadingDiffGenerationStage.preparing,
      completedChunks: 0,
      totalChunks: 0,
    );
    const generating = ReadingDiffGenerationProgress(
      stage: ReadingDiffGenerationStage.generating,
      completedChunks: 1,
      totalChunks: 4,
      currentChunk: 2,
    );
    const repairing = ReadingDiffGenerationProgress(
      stage: ReadingDiffGenerationStage.repairing,
      completedChunks: 1,
      totalChunks: 4,
      currentChunk: 2,
    );
    const combining = ReadingDiffGenerationProgress(
      stage: ReadingDiffGenerationStage.combining,
      completedChunks: 4,
      totalChunks: 4,
    );

    expect(preparing.label, 'Preparing reading diff');
    expect(preparing.fraction, isNull);
    expect(generating.label, 'Generating chunk 2 of 4');
    expect(generating.fraction, 0.25);
    expect(repairing.label, 'Repairing chunk 2 of 4');
    expect(combining.label, 'Combining 4 chunks');
    expect(combining.fraction, 1);
  });

  test(
    'reading diff prompts preserve immutable coordinates and repair data',
    () {
      final preparation = rust.ReadingDiffPreparation(
        rawBytes: BigInt.from(20),
        schemaVersion: 1,
        rubricVersion: 'rubric-v1',
        planSchema: '{}',
        chunks: <rust.ReadingDiffChunk>[],
      );
      final chunk = rust.ReadingDiffChunk(
        index: 0,
        rawDiff: Uint8List.fromList(<int>[1]),
        numberedDiff: '1|diff --git a/a b/a',
      );
      final prompt = buildReadingDiffPrompt(
        preparation: rust.ReadingDiffPreparation(
          rawBytes: preparation.rawBytes,
          schemaVersion: preparation.schemaVersion,
          rubricVersion: preparation.rubricVersion,
          planSchema: preparation.planSchema,
          chunks: <rust.ReadingDiffChunk>[chunk],
        ),
        chunk: chunk,
        customInstructions: 'Keep security checks.',
      );
      expect(prompt, contains('MeatPlanV1'));
      expect(prompt, contains('<output_schema>'));
      expect(prompt, contains('{}'));
      expect(prompt, contains('1|diff --git a/a b/a'));
      expect(prompt, contains('Keep security checks.'));
      final repair = buildReadingDiffRepairPrompt(
        originalPrompt: prompt,
        rejectedPlan: '{"version":1}',
        compilerError: 'missing summary',
      );
      expect(repair, contains('missing summary'));
      expect(repair, contains('{"version":1}'));
    },
  );

  test(
    'file cache atomically replaces and reloads successful results',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'alera-reading-diff-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final cache = FileReadingDiffCache(
        directoryProvider: () async => directory,
      );
      ReadingDiffResult result(String summary) => ReadingDiffResult(
        diff: Uint8List.fromList(<int>[0, 255, 10]),
        summary: summary,
        changedLines: 3,
        retainedChangedLines: 2,
        agentLabel: 'Claude Code',
      );

      await cache.write('cache-key', result('First.'));
      await cache.write('cache-key', result('Second.'));
      final cached = await cache.read('cache-key');
      expect(cached?.summary, 'Second.');
      expect(cached?.diff, <int>[0, 255, 10]);
      expect(cached?.fromCache, isTrue);
      final files = await Directory(
        '${directory.path}${Platform.pathSeparator}reading-diffs',
      ).list().toList();
      expect(files, hasLength(1));
    },
  );
}
