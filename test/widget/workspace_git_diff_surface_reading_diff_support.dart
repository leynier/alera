part of 'workspace_git_diff_surface_test.dart';

class _BlockingReadingDiffService extends ReadingDiffService {
  _BlockingReadingDiffService(
    FakeGitBackend backend, {
    this.completeOnCancel = true,
  }) : super(
         gitBackend: backend,
         runner: const _FailingReadingDiffRunner(),
         cache: const _EmptyReadingDiffCache(),
       );

  final List<ReadingDiffRequest> started = <ReadingDiffRequest>[];
  final List<ReadingDiffRequest> canceled = <ReadingDiffRequest>[];
  final bool completeOnCancel;
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
    if (completeOnCancel) {
      completeCancellation();
    }
  }

  void completeCancellation() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const AiAssistCanceledException());
    }
  }
}

class _BlockingPreparationReadingDiffService extends ReadingDiffService {
  _BlockingPreparationReadingDiffService(FakeGitBackend backend)
    : super(
        gitBackend: backend,
        runner: const _FailingReadingDiffRunner(),
        cache: const _EmptyReadingDiffCache(),
      );

  final List<ReadingDiffRequest> canceled = <ReadingDiffRequest>[];
  final Completer<ReadingDiffPreparation> _pending =
      Completer<ReadingDiffPreparation>();
  ReadingDiffRequest? _request;

  @override
  Future<ReadingDiffPreparation> prepare(ReadingDiffRequest request) {
    _request = request;
    return _pending.future;
  }

  @override
  void cancel(ReadingDiffRequest request) {
    canceled.add(request);
  }

  void completePreparation() {
    _pending.complete(_preparation(_request!, cacheKey: 'preparation'));
  }
}

class _FailingReadingDiffRunner implements AgentTaskRunner {
  const _FailingReadingDiffRunner();

  @override
  void cancel(String runId) {}

  @override
  Future<AiAssistAgentRunResult> run(AiAssistAgentRunRequest request) {
    throw const AiAssistException(
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

class _CachedReadingDiffService extends ReadingDiffService {
  _CachedReadingDiffService(FakeGitBackend backend)
    : super(
        gitBackend: backend,
        runner: const _FailingReadingDiffRunner(),
        cache: const _EmptyReadingDiffCache(),
      );

  final ReadingDiffResult result = _readingDiffResult();

  @override
  Future<ReadingDiffPreparation> prepare(ReadingDiffRequest request) async =>
      _preparation(
        request,
        cacheKey: 'cached-reading-diff',
        cachedResult: result,
      );

  @override
  Future<ReadingDiffResult> generate(
    ReadingDiffPreparation preparation, {
    void Function(ReadingDiffGenerationProgress progress)? onProgress,
  }) async => result;
}

class _RegenerationFailureReadingDiffService extends ReadingDiffService {
  _RegenerationFailureReadingDiffService(FakeGitBackend backend)
    : super(
        gitBackend: backend,
        runner: const _FailingReadingDiffRunner(),
        cache: const _EmptyReadingDiffCache(),
      );

  final ReadingDiffResult result = _readingDiffResult();
  var preparationCount = 0;

  @override
  Future<ReadingDiffPreparation> prepare(ReadingDiffRequest request) async {
    preparationCount += 1;
    return _preparation(
      request,
      cacheKey: 'regeneration-$preparationCount',
      cachedResult: preparationCount == 1 ? result : null,
      addedLine: preparationCount == 1
          ? 'snapshot-value'
          : 'replacement-snapshot',
    );
  }

  @override
  Future<ReadingDiffResult> generate(
    ReadingDiffPreparation preparation, {
    void Function(ReadingDiffGenerationProgress progress)? onProgress,
  }) async {
    if (preparationCount == 1) {
      return result;
    }
    throw const AiAssistException('Replacement generation failed.');
  }
}

ReadingDiffPreparation _preparation(
  ReadingDiffRequest request, {
  required String cacheKey,
  ReadingDiffResult? cachedResult,
  String addedLine = 'snapshot-value',
}) => ReadingDiffPreparation(
  request: request,
  rawDiff: Uint8List.fromList(
    'diff --git a/lib/main.dart b/lib/main.dart\n'
            '--- a/lib/main.dart\n'
            '+++ b/lib/main.dart\n'
            '@@ -1 +1 @@\n'
            '-old-value\n'
            '+$addedLine\n'
        .codeUnits,
  ),
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
  agent: AiAssistAgent.codex,
  model: 'gpt-5.5',
  effort: 'low',
  accessPolicy: AgentTaskAccessPolicy.diffOnly,
  cacheKey: cacheKey,
  cachedResult: cachedResult,
);

ReadingDiffResult _readingDiffResult() => ReadingDiffResult(
  diff: Uint8List.fromList(
    'diff --git a/lib/main.dart b/lib/main.dart\n'
            '--- a/lib/main.dart\n'
            '+++ b/lib/main.dart\n'
            '@@ -1 +1 @@\n'
            '-old\n'
            '+new\n'
        .codeUnits,
  ),
  summary: 'Update the value.',
  changedLines: 2,
  retainedChangedLines: 2,
  agentLabel: 'Codex',
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
