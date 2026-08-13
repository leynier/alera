part of 'workspace_git_diff_surface_test.dart';

void _registerWorkspaceGitDiffSurfaceReadingDiffTests() {
  testWidgets('diff surface cancels the request from the replaced tab', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/old.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+new')],
            added: 1,
            removed: 0,
          ),
        ],
      );
    final service = _BlockingReadingDiffService(backend);
    final oldTab = _diffTab(
      filePath: 'lib/old.dart',
      oldPath: 'lib/older.dart',
      title: 'old.dart',
    );

    await _pumpDiffSurface(
      tester,
      backend: backend,
      tab: oldTab,
      readingDiffService: service,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Generate Reading Diff'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate Reading Diff').last);
    await tester.pump();
    expect(service.started.single.filePath, 'lib/old.dart');
    expect(service.started.single.oldPath, 'lib/older.dart');

    await _pumpDiffSurface(
      tester,
      backend: backend,
      tab: _diffTab(filePath: 'lib/new.dart', title: 'new.dart'),
      readingDiffService: service,
    );
    await tester.pumpAndSettle();

    expect(service.canceled.single.filePath, 'lib/old.dart');
  });

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

class _BlockingReadingDiffService extends ReadingDiffService {
  _BlockingReadingDiffService(FakeGitBackend backend)
    : super(
        gitBackend: backend,
        runner: const _FailingReadingDiffRunner(),
        cache: const _EmptyReadingDiffCache(),
      );

  final List<ReadingDiffRequest> started = <ReadingDiffRequest>[];
  final List<ReadingDiffRequest> canceled = <ReadingDiffRequest>[];
  Completer<ReadingDiffResult>? _pending;

  @override
  Future<ReadingDiffPreparation> prepare(ReadingDiffRequest request) async =>
      _preparation(request, cacheKey: request.filePath ?? 'all');

  @override
  Future<ReadingDiffResult> generate(
    ReadingDiffPreparation preparation, {
    void Function(ReadingDiffGenerationProgress progress)? onProgress,
  }) {
    started.add(preparation.request);
    _pending = Completer<ReadingDiffResult>();
    return _pending!.future;
  }

  @override
  void cancel(ReadingDiffRequest request) {
    canceled.add(request);
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const AiTextGenerationCanceledException());
    }
  }
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
    return _preparation(request, cacheKey: 'reading-diff-error');
  }
}

ReadingDiffPreparation _preparation(
  ReadingDiffRequest request, {
  required String cacheKey,
}) => ReadingDiffPreparation(
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
        continuationPreamble: Uint8List(0),
      ),
    ],
  ),
  agent: AiTextGenerationAgent.codex,
  model: 'gpt-5.5',
  effort: 'low',
  accessPolicy: AgentTaskAccessPolicy.diffOnly,
  cacheKey: cacheKey,
);

class _EmptyReadingDiffCache implements ReadingDiffCache {
  const _EmptyReadingDiffCache();

  @override
  Future<ReadingDiffResult?> read(String key) async => null;

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> write(String key, ReadingDiffResult result) async {}
}
