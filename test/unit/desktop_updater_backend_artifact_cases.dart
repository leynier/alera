part of 'desktop_updater_backend_test.dart';

void registerDesktopUpdaterBackendArtifactTests() {
  test('cancels an artifact response when the backend is disposed', () async {
    final bodyStarted = Completer<void>();
    final releaseBody = Completer<void>();
    final artifactServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    artifactServer.listen((request) async {
      try {
        request.response.add(<int>[1]);
        await request.response.flush();
        if (!bodyStarted.isCompleted) {
          bodyStarted.complete();
        }
        await releaseBody.future;
      } on Object {
        // Disposal closes the response while this test holds it open.
      }
    });
    try {
      final fixture = await _signedFixture(
        descriptorPlatform: 'linux',
        indexPlatform: 'linux',
        artifactUrl: Uri.parse(
          'http://127.0.0.1:${artifactServer.port}/artifact.zip',
        ),
        artifactLength: 4,
      );
      final backend = DesktopUpdaterBackend(
        client: _metadataClient(fixture),
        artifactTimeout: const Duration(seconds: 1),
      );
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

      await bodyStarted.future;
      backend.dispose();

      await expectLater(
        download.timeout(const Duration(seconds: 1)),
        throwsA(isA<UpdateDownloadCancelledException>()),
      );
      releaseBody.complete();
    } finally {
      if (!releaseBody.isCompleted) {
        releaseBody.complete();
      }
      await artifactServer.close(force: true);
    }
  });

  test('cleans staging when disposal overlaps transport cleanup', () async {
    final parent = await Directory.systemTemp.createTemp(
      'alera-updater-overlap',
    );
    final stagingRoot = Directory('${parent.path}/desktop_updater_stage_zip')
      ..createSync();
    final sibling = Directory('${parent.path}/keep-me')..createSync();
    late DesktopUpdaterBackend backend;
    final fixture = await _signedFixture(
      descriptorPlatform: 'linux',
      indexPlatform: 'linux',
      artifactLength: 4,
    );
    final result = Completer<UpdateStageResult>();
    final updater = _DelayedUpdater(result.future);
    backend = DesktopUpdaterBackend(
      updater: updater,
      client: _metadataClient(fixture),
      afterTransportCancelForTesting: () => backend.dispose(),
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
      expect(parent.existsSync(), isTrue);
    } finally {
      backend.dispose();
      if (!result.isCompleted) {
        result.completeError(StateError('cleanup test stopped early'));
      }
      if (parent.existsSync()) {
        parent.deleteSync(recursive: true);
      }
    }
  });

  test('cleans only the owned staging root for a macOS pkg result', () async {
    final parent = await Directory.systemTemp.createTemp(
      'alera-updater-cleanup',
    );
    final stagingRoot = Directory('${parent.path}/desktop_updater_stage_pkg')
      ..createSync();
    final sibling = Directory('${parent.path}/keep-me')..createSync();
    final result = Completer<UpdateStageResult>();
    final updater = _DelayedUpdater(result.future);
    try {
      final fixture = await _signedFixture(
        descriptorPlatform: 'macos',
        artifactKind: 'pkgInstaller',
      );
      final backend = DesktopUpdaterBackend(
        updater: updater,
        client: _metadataClient(fixture),
      );
      final candidate = await backend.checkForUpdate(
        archiveUrl: _archiveUrl,
        channel: 'stable',
        currentVersion: '1.0.0',
        currentBuildNumber: '1',
        platform: 'macos',
        requireSignature: true,
        publicKeyId: _publicKeyId,
        publicKeyBase64: fixture.publicKey,
      );
      final download = backend.downloadAndStage(candidate!);

      backend.dispose();
      result.complete(
        UpdateStageResult(
          descriptor: ReleaseDescriptor.fromJson(fixture.descriptor),
          stagingPath: stagingRoot.path,
        ),
      );

      await expectLater(download, throwsA(isA<StateError>()));
      expect(stagingRoot.existsSync(), isFalse);
      expect(sibling.existsSync(), isTrue);
      expect(parent.existsSync(), isTrue);
    } finally {
      if (!result.isCompleted) {
        result.completeError(StateError('cleanup test stopped early'));
      }
      if (parent.existsSync()) {
        parent.deleteSync(recursive: true);
      }
    }
  });
}

class _DelayedUpdater extends DesktopUpdater {
  _DelayedUpdater(this.result);

  final Future<UpdateStageResult> result;

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
  }) {
    return result;
  }
}
