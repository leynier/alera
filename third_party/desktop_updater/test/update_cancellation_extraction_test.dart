import "dart:async";
import "dart:io";

import "package:archive/archive.dart";
import "package:crypto/crypto.dart" as crypto;
import "package:desktop_updater/desktop_updater.dart";
import "package:desktop_updater/src/core/update_client.dart";
import "package:desktop_updater/src/io/update_transport.dart";
import "package:flutter_test/flutter_test.dart";
import "package:path/path.dart" as path;

void main() {
  test("uses the injected process runner for external URL handoff", () async {
    String? executable;
    List<String>? arguments;
    await defaultExternalUrlLauncher(
      Uri.parse("https://updates.example.test"),
      runProcess: (actualExecutable, actualArguments) async {
        executable = actualExecutable;
        arguments = actualArguments;
        return ProcessResult(1, 0, "", "");
      },
    );

    expect(executable, "xdg-open");
    expect(arguments, ["https://updates.example.test"]);
  });

  test("extracts in a worker and uses the injected mode applier", () async {
    final root = await Directory.systemTemp.createTemp("desktop_updater_api_");
    try {
      final executable = ArchiveFile.string("bin/alera", "binary");
      executable.mode = 0x81ED;
      final archive = File(path.join(root.path, "artifact.zip"))
        ..writeAsBytesSync(
          ZipEncoder().encode(Archive()..addFile(executable)),
        );
      final modes = <({int mode, List<String> paths})>[];

      await const SafeZipExtractor().extract(
        archiveFile: archive,
        destination: Directory(path.join(root.path, "staged")),
        platform: "linux",
        applyFileMode: (mode, paths, _) async {
          modes.add((mode: mode, paths: List<String>.from(paths)));
        },
      );

      expect(
        File(path.join(root.path, "staged", "bin", "alera")).existsSync(),
        isTrue,
      );
      expect(modes, hasLength(1));
      expect(modes.single.mode, 0x1ED);
      expect(
        modes.single.paths.single,
        endsWith(path.join("staged", "bin", "alera")),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test("cancellation terminates extraction before the worker completes",
      () async {
    final root =
        await Directory.systemTemp.createTemp("desktop_updater_cancel_");
    final token = UpdateCancellationToken();
    try {
      final archive = Archive();
      for (var index = 0; index < 128; index++) {
        archive.addFile(
          ArchiveFile.string("files/$index.txt", "x" * (64 * 1024)),
        );
      }
      final archiveFile = File(path.join(root.path, "artifact.zip"))
        ..writeAsBytesSync(ZipEncoder().encode(archive));
      final extraction = const SafeZipExtractor().extract(
        archiveFile: archiveFile,
        destination: Directory(path.join(root.path, "staged")),
        platform: "linux",
        cancellationToken: token,
      );
      scheduleMicrotask(token.cancel);

      await expectLater(extraction, throwsA(isA<UpdateCancelledException>()));
      await root.delete(recursive: true);
      expect(root.existsSync(), isFalse);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  test("cancellation closes a cancellable download transport", () async {
    final transport = _CancellableTransport();
    final token = UpdateCancellationToken();
    final descriptor = ReleaseDescriptor.fromJson({
      "schemaVersion": 3,
      "packageId": "dev.example.alera",
      "appName": "Alera",
      "version": "2.0.0",
      "buildNumber": 2,
      "generatedAt": "2026-07-27T00:00:00.000Z",
      "platform": "linux",
      "channel": "stable",
      "artifact": {
        "kind": "zip",
        "url": "https://updates.example.test/artifact.zip",
        "sha256": "0" * 64,
        "length": 1,
      },
      "install": {"strategy": "wholeDirectoryReplace"},
      "minimumUpdaterVersion": "2.5.0",
    });
    final staging = UpdateClient(
      appArchiveUrl: Uri.parse("https://updates.example.test/archive"),
      currentVersion: DesktopVersionInfo.parse("1.0.0"),
      platform: "linux",
      transport: transport,
    ).downloadVerifyAndStage(
      descriptor: descriptor,
      cancellationToken: token,
    );
    scheduleMicrotask(token.cancel);

    await expectLater(staging, throwsA(isA<UpdateCancelledException>()));
    expect(transport.wasCancelled, isTrue);
  });

  test("staging cleanup failure preserves the original update error", () async {
    final root = await Directory.systemTemp.createTemp(
      "desktop_updater_cleanup_error_",
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final artifactBytes = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile.string("app.txt", "update")),
    );
    final artifact = File(path.join(root.path, "artifact.zip"));
    await artifact.writeAsBytes(artifactBytes);
    final descriptor = ReleaseDescriptor(
      schemaVersion: 3,
      packageId: "dev.example.app",
      appName: "Example",
      version: "2.0.0",
      buildNumber: 2,
      platform: "linux",
      channel: "stable",
      artifact: ReleaseArtifact(
        kind: "zip",
        url: artifact.uri,
        sha256: crypto.sha256.convert(artifactBytes).toString(),
        length: artifactBytes.length,
      ),
      install: const ReleaseInstall(strategy: "wholeDirectoryReplace"),
      minimumUpdaterVersion: "2.0.0",
      generatedAt: DateTime.utc(2026, 7, 27),
    );
    final primaryError = StateError("primary staging failure");
    var cleanupCalled = false;
    final client = UpdateClient(
      appArchiveUrl: Uri.parse("https://updates.example.test/archive"),
      currentVersion: DesktopVersionInfo.parse("1.0.0"),
      platform: "linux",
      stagingParent: root,
      extractor: _FailingExtractor(primaryError),
      cleanupStagingDirectory: (stagingRoot) async {
        cleanupCalled = true;
        throw FileSystemException(
          "secondary staging cleanup failure",
          stagingRoot.path,
        );
      },
    );

    await expectLater(
      client.downloadVerifyAndStage(descriptor: descriptor),
      throwsA(same(primaryError)),
    );
    expect(cleanupCalled, isTrue);
  });

  test(
    "public DMG staging detaches with the cleanup runner after ditto cancel",
    () async {
      final root = await Directory.systemTemp.createTemp(
        "desktop_updater_dmg_cancel_",
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final artifact = File(path.join(root.path, "Example.dmg"));
      final bytes = <int>[1, 2, 3, 4];
      await artifact.writeAsBytes(bytes);
      final descriptor = ReleaseDescriptor(
        schemaVersion: 3,
        packageId: "com.example.app",
        appName: "Example",
        version: "2.0.0",
        buildNumber: 2,
        platform: "macos",
        channel: "stable",
        artifact: ReleaseArtifact(
          kind: "dmg",
          url: artifact.uri,
          sha256: crypto.sha256.convert(bytes).toString(),
          length: bytes.length,
        ),
        install: const ReleaseInstall(
          strategy: "wholeBundleReplace",
          macosDmg: ReleaseMacOSDmgInstall(
            appBundleName: "Example.app",
            verifyPrimarySignature: false,
          ),
        ),
        minimumUpdaterVersion: "2.0.0",
        generatedAt: DateTime.utc(2026, 7, 27),
      );
      final dittoStarted = Completer<void>();
      final allowDittoExit = Completer<void>();
      final operationCommands = <String>[];
      final cleanupCommands = <String>[];

      Future<ProcessResult> runProcess(
        String executable,
        List<String> arguments,
      ) async {
        operationCommands.add([executable, ...arguments].join(" "));
        if (executable == "/usr/bin/hdiutil") {
          return ProcessResult(0, 0, "", "");
        }
        if (executable == "/usr/bin/ditto") {
          if (!dittoStarted.isCompleted) {
            dittoStarted.complete();
          }
          await allowDittoExit.future;
          return ProcessResult(0, 0, "", "");
        }
        throw StateError("Unexpected operation command: $executable");
      }

      Future<ProcessResult> runCleanupProcess(
        String executable,
        List<String> arguments,
      ) async {
        cleanupCommands.add([executable, ...arguments].join(" "));
        return ProcessResult(0, 0, "", "");
      }

      final cancellation = UpdateCancellationToken();
      final staging = DesktopUpdater().downloadZipFirstUpdate(
        appArchiveUrl: Uri.parse("https://updates.example.test/archive"),
        currentVersion: DesktopVersionInfo.parse("1.0.0"),
        descriptor: descriptor,
        runProcess: runProcess,
        runCleanupProcess: runCleanupProcess,
        cancellationToken: cancellation,
      );

      await dittoStarted.future;
      cancellation.cancel();
      allowDittoExit.complete();

      await expectLater(
        staging,
        throwsA(isA<UpdateCancelledException>()),
      );
      expect(operationCommands, hasLength(2));
      expect(operationCommands.first, contains("hdiutil attach"));
      expect(operationCommands.last, contains("ditto"));
      expect(
        operationCommands,
        everyElement(isNot(contains("hdiutil detach"))),
      );
      expect(cleanupCommands, hasLength(1));
      expect(cleanupCommands.single, contains("hdiutil detach"));
    },
    skip: !Platform.isMacOS,
  );
}

class _CancellableTransport
    implements UpdateTransport, CancellableUpdateTransport {
  final Completer<void> _cancelled = Completer<void>();
  bool wasCancelled = false;

  @override
  Future<void> download(
    Uri source,
    File destination, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    Duration? timeout,
  }) async {
    await _cancelled.future;
    throw const SocketException("cancelled");
  }

  @override
  Future<void> cancel() async {
    wasCancelled = true;
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

class _FailingExtractor extends SafeZipExtractor {
  _FailingExtractor(this.error);

  final Object error;

  @override
  Future<void> extract({
    required File archiveFile,
    required Directory destination,
    String platform = "",
    bool rejectSymlinks = true,
    bool requireDittoForMacOS = true,
    UpdateCancellationToken? cancellationToken,
    FileModeApplier applyFileMode = defaultFileModeApplier,
  }) {
    return Future<void>.error(error);
  }
}
