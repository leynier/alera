import 'dart:typed_data';

import 'package:alera/src/features/ai_text_generation/application/ai_text_agent_runner.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/features/reading_diff/domain/reading_diff_models.dart';
import 'package:alera/src/features/reading_diff/presentation/reading_diff_confirmation_dialog.dart';
import 'package:alera/src/features/reading_diff/presentation/reading_diff_view.dart';
import 'package:alera/src/rust/api/reading_diff.dart' as rust;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('confirmation discloses quota, provider transfer and access', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReadingDiffConfirmationDialog(preparation: _preparation()),
      ),
    );

    expect(find.text('Generate Reading Diff'), findsNWidgets(2));
    expect(
      find.textContaining('consumes its subscription quota'),
      findsOneWidget,
    );
    expect(find.textContaining('configured provider'), findsOneWidget);
    expect(find.text('Repository Read Only'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('reading view shows summary, retention, cache and diff rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 500,
          child: ReadingDiffView(
            result: ReadingDiffResult(
              diff: Uint8List.fromList('+new\n-old\n'.codeUnits),
              summary: 'Keep the behavioral change.',
              changedLines: 4,
              retainedChangedLines: 2,
              agentLabel: 'Codex',
              fromCache: true,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('Keep the behavioral change. Kept 2/4 changed lines (cached).'),
      findsOneWidget,
    );
    expect(find.text('+new'), findsOneWidget);
    expect(find.text('-old'), findsOneWidget);
  });
}

ReadingDiffPreparation _preparation() {
  final request = ReadingDiffRequest(
    workspacePath: '/repo',
    settings: AiTextGenerationSettings.defaults,
  );
  return ReadingDiffPreparation(
    request: request,
    rawDiff: Uint8List.fromList(<int>[1]),
    compiler: rust.ReadingDiffPreparation(
      rawBytes: BigInt.from(1024),
      schemaVersion: 1,
      rubricVersion: 'rubric-v1',
      planSchema: '{}',
      chunks: <rust.ReadingDiffChunk>[
        rust.ReadingDiffChunk(
          index: 0,
          rawDiff: Uint8List.fromList(<int>[1]),
          numberedDiff: '1|diff --git a/a b/a',
        ),
      ],
    ),
    agent: AiTextGenerationAgent.codex,
    model: 'gpt-5.5',
    effort: 'medium',
    accessPolicy: AgentTaskAccessPolicy.repositoryReadOnly,
    cacheKey: 'key',
  );
}
