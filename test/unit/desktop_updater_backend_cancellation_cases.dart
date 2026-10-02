part of 'desktop_updater_backend_test.dart';

void registerDesktopUpdaterBackendCancellationTests() {
  test(
    'passes staging hooks and cancels them before rejecting stale success',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'alera-updater-cancel',
      );
      final stagingRoot = Directory(
        '${parent.path}/desktop_updater_stage_cancel',
      )..createSync();
      final sibling = Directory('${parent.path}/keep-me')..createSync();
      final started = Completer<void>();
      final result = Completer<UpdateStageResult>();
      final updater = _CapturingUpdater(
        started: started,
        result: result.future,
      );
      final processRunner = _RecordingProcessRunner();
      final cleanupRecords = <LogRecord>[];
      final cleanupSubscription = Logger.root.onRecord
          .where((record) => record.loggerName == 'DesktopUpdaterBackend')
          .listen(cleanupRecords.add);
      addTearDown(cleanupSubscription.cancel);
      final fixture = await _signedFixture(
        descriptorPlatform: 'linux',
        indexPlatform: 'linux',
        artifactLength: 4,
      );
      final backend = DesktopUpdaterBackend(
        updater: updater,
        client: _metadataClient(fixture),
        processRunner: processRunner,
        artifactTimeout: const Duration(seconds: 1),
      );

      try {
        final candidate = await backend.checkForUpdate(
          archiveUrl: _archiveUrl,
          channel: 'stable',
          currentVersion: '1.0.0',
          currentBuildNumber: '1',
          platform: 'linux',
          requireSignature: true,
          publicKeyId: _publicKeyId,
          publicKeyBase64: fixture.publicKey,
        );
        final download = backend.downloadAndStage(candidate!);
        await started.future;

        expect(updater.runProcess, isNotNull);
        expect(updater.applyFileMode, isNotNull);
        expect(updater.cancellationToken, isNotNull);
        expect(updater.runProcess, isNot(same(defaultProcessRunner)));
        expect(updater.runCleanupProcess, isNotNull);
        expect(updater.runCleanupProcess, isNot(same(defaultProcessRunner)));
        expect(updater.runCleanupProcess, isNot(same(updater.runProcess)));
        expect(updater.applyFileMode, isNot(same(defaultFileModeApplier)));
        await updater.applyFileMode!(
          0,
          const <String>[],
          updater.cancellationToken,
        );

        backend.dispose();
        await updater.cancellationToken!.whenCancelled.timeout(
          const Duration(seconds: 1),
        );
        expect(updater.cancellationToken!.isCancelled, isTrue);
        await expectLater(
          updater.runProcess!('normal-tool', const []),
          throwsA(isA<UpdateCancelledException>()),
        );
        expect(processRunner.starts, 0);
        final cleanupResult = await updater.runCleanupProcess!(
          'cleanup-tool',
          const [],
        );
        expect(cleanupResult.exitCode, 0);
        expect(processRunner.starts, 1);
        processRunner.exitCode = 1;
        final failedCleanupResult = await updater.runCleanupProcess!(
          'cleanup-tool',
          const [],
        );
        expect(failedCleanupResult.exitCode, 1);
        expect(processRunner.starts, 2);
        expect(cleanupRecords, hasLength(1));
        final cleanupRecord = cleanupRecords.single;
        expect(cleanupRecord.message, 'Update cleanup command failed.');
        expect(cleanupRecord.error, isA<ProcessException>());
        expect((cleanupRecord.error! as ProcessException).errorCode, 1);

        result.complete(
          UpdateStageResult(
            descriptor: ReleaseDescriptor.fromJson(fixture.descriptor),
            stagingPath: stagingRoot.path,
          ),
        );
        await expectLater(
          download.timeout(const Duration(seconds: 1)),
          throwsA(isA<StateError>()),
        );
        expect(stagingRoot.existsSync(), isFalse);
        expect(sibling.existsSync(), isTrue);
      } finally {
        backend.dispose();
        if (!result.isCompleted) {
          result.completeError(StateError('cancellation test stopped early'));
        }
        if (parent.existsSync()) {
          parent.deleteSync(recursive: true);
        }
      }
    },
  );

  test('rejects a concurrent staging request during extraction', () async {
    final parent = await Directory.systemTemp.createTemp(
      'alera-updater-concurrent',
    );
    final stagingRoot = Directory(
      '${parent.path}/desktop_updater_stage_concurrent',
    )..createSync();
    final started = Completer<void>();
    final extractionEntered = Completer<void>();
    final extractionGate = Completer<void>();
    final result = Completer<UpdateStageResult>();
    final updater = _CapturingUpdater(
      started: started,
      result: result.future,
      extractionEntered: extractionEntered,
      extractionGate: extractionGate.future,
    );
    final fixture = await _signedFixture(
      descriptorPlatform: 'linux',
      indexPlatform: 'linux',
      artifactLength: 4,
    );
    final backend = DesktopUpdaterBackend(
      updater: updater,
      client: _metadataClient(fixture),
      artifactTimeout: const Duration(seconds: 1),
    );

    try {
      final candidate = await backend.checkForUpdate(
        archiveUrl: _archiveUrl,
        channel: 'stable',
        currentVersion: '1.0.0',
        currentBuildNumber: '1',
        platform: 'linux',
        requireSignature: true,
        publicKeyId: _publicKeyId,
        publicKeyBase64: fixture.publicKey,
      );
      final first = backend.downloadAndStage(candidate!);
      await started.future;
      await extractionEntered.future;

      await expectLater(
        backend.downloadAndStage(candidate),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('already in progress'),
          ),
        ),
      );

      extractionGate.complete();
      result.complete(
        UpdateStageResult(
          descriptor: ReleaseDescriptor.fromJson(fixture.descriptor),
          stagingPath: stagingRoot.path,
        ),
      );
      final staged = await first;
      expect(staged, stagingRoot.path);
    } finally {
      backend.dispose();
      if (!extractionGate.isCompleted) {
        extractionGate.complete();
      }
      if (!result.isCompleted) {
        result.completeError(StateError('concurrency test stopped early'));
      }
      if (parent.existsSync()) {
        parent.deleteSync(recursive: true);
      }
    }
  });
}

class _CapturingUpdater extends DesktopUpdater {
  _CapturingUpdater({
    required this.started,
    required this.result,
    this.extractionEntered,
    this.extractionGate,
  });

  final Completer<void> started;
  final Future<UpdateStageResult> result;
  final Completer<void>? extractionEntered;
  final Future<void>? extractionGate;
  ProcessRunner? runProcess;
  ProcessRunner? runCleanupProcess;
  FileModeApplier? applyFileMode;
  UpdateCancellationToken? cancellationToken;

  @override
  Future<UpdateStageResult> downloadZipFirstUpdate({
    required Uri appArchiveUrl,
    required DesktopVersionInfo currentVersion,
    required ReleaseDescriptor descriptor,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    UpdateRequestHeadersProvider? requestHeadersProvider,
    ProcessRunner runProcess = defaultProcessRunner,
    ProcessRunner? runCleanupProcess,
    FileModeApplier applyFileMode = defaultFileModeApplier,
    UpdateCancellationToken? cancellationToken,
  }) async {
    this.runProcess = runProcess;
    this.runCleanupProcess = runCleanupProcess;
    this.applyFileMode = applyFileMode;
    this.cancellationToken = cancellationToken;
    if (!started.isCompleted) {
      started.complete();
    }
    final gate = extractionGate;
    if (gate != null) {
      await applyFileMode(0, const <String>[], cancellationToken);
      extractionEntered?.complete();
      await gate;
    }
    return result;
  }
}

class _RecordingProcessRunner implements alera_process.ProcessRunner {
  var starts = 0;
  var exitCode = 0;

  @override
  Future<alera_process.ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return const alera_process.ProcessRunOutput(
      exitCode: 0,
      stdout: '',
      stderr: '',
    );
  }

  @override
  Future<alera_process.StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async {
    starts++;
    return alera_process.StartedProcess(
      stdinWrite: (_) {},
      stdout: Stream<List<int>>.empty(),
      stderr: Stream<List<int>>.empty(),
      pid: 1,
      exitCode: Future<int>.value(exitCode),
      kill: ([dynamic signal]) => true,
    );
  }
}
