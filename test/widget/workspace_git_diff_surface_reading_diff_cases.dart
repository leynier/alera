part of 'workspace_git_diff_surface_test.dart';

void _registerWorkspaceGitDiffSurfaceReadingDiffTests() {
  testWidgets('diff surface keeps reading diff failures visible', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/main.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+new')],
            added: 1,
            removed: 1,
          ),
        ],
      )
      ..readingDiffPatchResult = Uint8List.fromList(
        'diff --git a/lib/main.dart b/lib/main.dart\n'
                '--- a/lib/main.dart\n'
                '+++ b/lib/main.dart\n'
                '@@ -1 +1 @@\n'
                '-old\n'
                '+new\n'
            .codeUnits,
      );
    final readingDiffService = _PreparedReadingDiffService(backend);

    await _pumpDiffSurface(
      tester,
      backend: backend,
      readingDiffService: readingDiffService,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Generate Reading Diff'));
    await tester.pumpAndSettle();
    expect(find.text('Generate Reading Diff'), findsNWidgets(2));
    await tester.tap(find.text('Generate Reading Diff').last);
    await tester.pumpAndSettle();

    expect(find.text('Reading diff generation failed'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      'Codex failed: Invalid schema for response format.',
    );
  });
}

class _FailingReadingDiffRunner implements AgentTaskRunner {
  const _FailingReadingDiffRunner();

  @override
  void cancel(String runId) {}

  @override
  Future<AiTextAgentRunResult> run(AiTextAgentRunRequest request) {
    throw const AiTextGenerationException(
      'Codex failed: Invalid schema for response format.',
    );
  }
}

class _PreparedReadingDiffService extends ReadingDiffService {
  _PreparedReadingDiffService(FakeGitBackend backend)
    : super(
        gitBackend: backend,
        runner: const _FailingReadingDiffRunner(),
        cache: const _EmptyReadingDiffCache(),
      );

  @override
  Future<ReadingDiffPreparation> prepare(ReadingDiffRequest request) async {
    return ReadingDiffPreparation(
      request: request,
      rawDiff: Uint8List.fromList(<int>[1]),
      compiler: rust.ReadingDiffPreparation(
        rawBytes: BigInt.one,
        schemaVersion: 1,
        rubricVersion: 'rubric-v1',
        planSchema: '{"type":"object"}',
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
      effort: 'low',
      accessPolicy: AgentTaskAccessPolicy.diffOnly,
      cacheKey: 'reading-diff-error',
    );
  }
}

class _EmptyReadingDiffCache implements ReadingDiffCache {
  const _EmptyReadingDiffCache();

  @override
  Future<ReadingDiffResult?> read(String key) async => null;

  @override
  Future<void> write(String key, ReadingDiffResult result) async {}
}

IconButton _openFileButton(WidgetTester tester) {
  final finder = find.ancestor(
    of: find.byIcon(AleraIcons.external),
    matching: find.byType(IconButton),
  );
  return tester.widget<IconButton>(finder);
}

Workspace _workspace() {
  final now = DateTime.utc(2026, 6, 6);
  return Workspace(
    id: 'workspace-1',
    projectId: 'project-1',
    name: 'Main',
    path: '/tmp/project',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}
