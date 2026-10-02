import "dart:async";
import "dart:io";
import "dart:isolate";

import "package:archive/archive_io.dart";
import "package:desktop_updater/src/core/update_cancellation.dart";
import "package:desktop_updater/src/io/archive_path.dart";
import "package:desktop_updater/src/macos_update.dart";
import "package:path/path.dart" as path;

const _unixExecuteMask = 0x49; // Octal 0111.

/// Applies executable and directory modes after archive extraction.
///
/// Applications should inject a syscall-backed implementation. The default
/// keeps the package standalone for existing consumers.
typedef FileModeApplier = Future<void> Function(
  int mode,
  List<String> paths,
  UpdateCancellationToken? cancellationToken,
);

/// Extracts zip artifacts while rejecting unsafe paths and symlinks.
///
/// Input and output streams avoid reading the complete archive into the main
/// isolate. The archive decoder may still retain memory proportional to its
/// compressed entries; the worker keeps that cost off the UI isolate.
class SafeZipExtractor {
  /// Creates a safe zip extractor.
  const SafeZipExtractor();

  /// Extracts [archiveFile] into [destination].
  Future<void> extract({
    required File archiveFile,
    required Directory destination,
    String platform = "",
    bool rejectSymlinks = true,
    bool requireDittoForMacOS = true,
    UpdateCancellationToken? cancellationToken,
    FileModeApplier applyFileMode = defaultFileModeApplier,
  }) async {
    final targetPlatform =
        platform.isEmpty ? Platform.operatingSystem : platform;
    if (targetPlatform == "macos" && requireDittoForMacOS) {
      throw UnsupportedError(
        "macOS app zips must be extracted with /usr/bin/ditto.",
      );
    }

    cancellationToken?.throwIfCancelled();
    final permissions = await _extractInWorker(
      archiveFile: archiveFile,
      destination: destination,
      rejectSymlinks: rejectSymlinks,
      cancellationToken: cancellationToken,
    );
    cancellationToken?.throwIfCancelled();
    await _applyUnixPermissions(
      permissions.filePermissions,
      targetPlatform,
      applyFileMode,
      cancellationToken,
    );

    for (final directory in permissions.directoryPermissions.entries) {
      cancellationToken?.throwIfCancelled();
      await _applyUnixPermissions(
        {
          directory.value: [directory.key],
        },
        targetPlatform,
        applyFileMode,
        cancellationToken,
      );
    }
  }
}

class _SafeZipExtractionResult {
  const _SafeZipExtractionResult({
    required this.filePermissions,
    required this.directoryPermissions,
  });

  final Map<int, List<String>> filePermissions;
  final Map<String, int> directoryPermissions;
}

Future<_SafeZipExtractionResult> _extractInWorker({
  required File archiveFile,
  required Directory destination,
  required bool rejectSymlinks,
  required UpdateCancellationToken? cancellationToken,
}) async {
  final resultPort = ReceivePort();
  final errorPort = ReceivePort();
  final exitPort = ReceivePort();
  final result = Completer<_SafeZipExtractionResult>();
  final workerExited = Completer<void>();
  final worker = await Isolate.spawn<List<Object?>>(
    _extractZipInWorker,
    [
      resultPort.sendPort,
      archiveFile.path,
      destination.path,
      rejectSymlinks,
    ],
    onError: errorPort.sendPort,
    onExit: exitPort.sendPort,
  );

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (result.isCompleted) {
      return;
    }
    result.completeError(error, stackTrace ?? StackTrace.current);
  }

  final resultSubscription = resultPort.listen((message) {
    if (result.isCompleted) {
      return;
    }
    if (message is! List<Object?> || message.isEmpty) {
      completeError(
        StateError("ZIP extraction worker returned an invalid result."),
      );
      return;
    }
    switch (message.first) {
      case "done":
        if (message.length != 4 ||
            message[1] is! Map<Object?, Object?> ||
            message[2] is! Map<Object?, Object?> ||
            message[3] is! SendPort) {
          completeError(
            StateError("ZIP extraction worker returned invalid permissions."),
          );
          return;
        }
        result.complete(
          _SafeZipExtractionResult(
            filePermissions: _decodeFilePermissions(
              message[1]! as Map<Object?, Object?>,
            ),
            directoryPermissions: _decodeDirectoryPermissions(
              message[2]! as Map<Object?, Object?>,
            ),
          ),
        );
        (message[3]! as SendPort).send(null);
      case "error":
        final error = message.length > 1 ? message[1] : null;
        final stack = message.length > 2 ? message[2] : null;
        completeError(
          _decodeWorkerError(error),
          stack is String ? StackTrace.fromString(stack) : null,
        );
        if (message.length > 3 && message[3] is SendPort) {
          (message[3]! as SendPort).send(null);
        }
      default:
        completeError(
          StateError("ZIP extraction worker returned an unknown result."),
        );
    }
  });
  final errorSubscription = errorPort.listen((message) {
    if (message is List<Object?> && message.isNotEmpty) {
      completeError(
        StateError(message.first.toString()),
        message.length > 1
            ? StackTrace.fromString(message[1].toString())
            : null,
      );
      return;
    }
    completeError(StateError("ZIP extraction worker failed."));
  });
  final exitSubscription = exitPort.listen((_) {
    if (!workerExited.isCompleted) {
      workerExited.complete();
    }
    if (!result.isCompleted) {
      completeError(StateError("ZIP extraction worker exited unexpectedly."));
    }
  });

  final cancellationSubscription = cancellationToken?.whenCancelled.then((_) {
    if (!result.isCompleted) {
      worker.kill(priority: Isolate.immediate);
      completeError(const UpdateCancelledException());
    }
  });

  try {
    return await result.future;
  } finally {
    worker.kill(priority: Isolate.immediate);
    await workerExited.future;
    cancellationSubscription?.ignore();
    await resultSubscription.cancel();
    await errorSubscription.cancel();
    await exitSubscription.cancel();
    resultPort.close();
    errorPort.close();
    exitPort.close();
  }
}

Future<void> _extractZipInWorker(List<Object?> message) async {
  final sendPort = message[0]! as SendPort;
  final acknowledgementPort = ReceivePort();

  Future<void> sendAndWaitForAcknowledgement(List<Object?> payload) async {
    payload.add(acknowledgementPort.sendPort);
    sendPort.send(payload);
    await acknowledgementPort.first;
  }

  try {
    final archiveFile = File(message[1]! as String);
    final destination = Directory(message[2]! as String);
    final rejectSymlinks = message[3]! as bool;
    final root = path.normalize(path.absolute(destination.path));
    _rejectSymlinkAncestors(root);
    destination.createSync(recursive: true);
    final input = InputFileStream(archiveFile.path);
    final filePermissions = <int, List<String>>{};
    final directoryPermissions = <String, int>{};

    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final entry in archive.files) {
        final relativePath = normalizeArchivePath(entry.name);
        if (relativePath.isEmpty) {
          continue;
        }
        if (entry.isSymbolicLink && rejectSymlinks) {
          throw FormatException("Zip entry is a symbolic link: ${entry.name}");
        }

        final destinationPath = path.normalize(path.join(root, relativePath));
        if (destinationPath != root && !path.isWithin(root, destinationPath)) {
          throw FormatException(
            "Zip entry escapes staging root: ${entry.name}",
          );
        }
        _rejectSymlinkComponents(root, destinationPath);

        if (entry.isDirectory) {
          Directory(destinationPath).createSync(recursive: true);
          _recordDirectoryPermissions(
            directoryPermissions,
            destinationPath,
            entry.unixPermissions,
          );
          continue;
        }

        Directory(path.dirname(destinationPath)).createSync(recursive: true);
        final output = OutputFileStream(destinationPath);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
        _recordFilePermissions(
          filePermissions,
          destinationPath,
          entry.unixPermissions,
        );
      }
      final sortedDirectoryPermissions = directoryPermissions.entries.toList()
        ..sort((a, b) => b.key.length.compareTo(a.key.length));
      await sendAndWaitForAcknowledgement([
        "done",
        filePermissions,
        <String, int>{
          for (final entry in sortedDirectoryPermissions)
            entry.key: entry.value,
        },
      ]);
    } finally {
      input.closeSync();
    }
  } on Object catch (error, stackTrace) {
    await sendAndWaitForAcknowledgement([
      "error",
      _encodeWorkerError(error),
      stackTrace.toString(),
    ]);
  } finally {
    acknowledgementPort.close();
  }
}

void _rejectSymlinkAncestors(String target) {
  var current = target;
  while (true) {
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw FormatException("Staging path contains a symbolic link: $current");
    }
    final parent = path.dirname(current);
    if (parent == current) {
      return;
    }
    current = parent;
  }
}

void _rejectSymlinkComponents(String root, String target) {
  final relative = path.relative(target, from: root);
  if (relative.isEmpty || relative == ".") {
    return;
  }
  var current = root;
  for (final component in path.split(relative)) {
    if (component.isEmpty || component == ".") {
      continue;
    }
    current = path.join(current, component);
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw FormatException("Staging path contains a symbolic link: $current");
    }
  }
}

List<Object?> _encodeWorkerError(Object error) {
  if (error is FormatException) {
    return ["format", error.message];
  }
  if (error is FileSystemException) {
    return [
      "filesystem",
      error.message,
      error.path,
      error.osError?.message,
      error.osError?.errorCode,
    ];
  }
  return ["state", error.toString()];
}

Object _decodeWorkerError(Object? encoded) {
  if (encoded is! List<Object?> || encoded.isEmpty) {
    return StateError("ZIP extraction worker failed.");
  }
  switch (encoded.first) {
    case "format":
      return FormatException(
        encoded.length > 1 ? encoded[1]?.toString() ?? "" : "",
      );
    case "filesystem":
      final message = encoded.length > 1 ? encoded[1]?.toString() : null;
      final filePath = encoded.length > 2 ? encoded[2]?.toString() : null;
      final osMessage = encoded.length > 3 ? encoded[3]?.toString() : null;
      final code =
          encoded.length > 4 && encoded[4] is int ? encoded[4]! as int : 0;
      return FileSystemException(
        message ?? "ZIP extraction failed.",
        filePath,
        OSError(osMessage ?? "ZIP extraction failed.", code),
      );
    default:
      return StateError(
        encoded.length > 1
            ? encoded[1]?.toString() ?? "ZIP extraction worker failed."
            : "ZIP extraction worker failed.",
      );
  }
}

Map<int, List<String>> _decodeFilePermissions(Map<Object?, Object?> encoded) {
  return {
    for (final entry in encoded.entries)
      int.parse(entry.key.toString()): [
        for (final path in (entry.value! as List<Object?>)) path.toString(),
      ],
  };
}

Map<String, int> _decodeDirectoryPermissions(Map<Object?, Object?> encoded) {
  return {
    for (final entry in encoded.entries)
      entry.key.toString(): int.parse(entry.value.toString()),
  };
}

void _recordFilePermissions(
  Map<int, List<String>> permissionsByMode,
  String filePath,
  int permissions,
) {
  if (permissions == 0) {
    return;
  }
  permissionsByMode.putIfAbsent(permissions, () => <String>[]).add(filePath);
}

void _recordDirectoryPermissions(
  Map<String, int> directoryPermissions,
  String directoryPath,
  int permissions,
) {
  if (permissions == 0 || (permissions & _unixExecuteMask) == 0) {
    return;
  }
  directoryPermissions[directoryPath] = permissions;
}

Future<void> _applyUnixPermissions(
  Map<int, List<String>> permissionsByMode,
  String targetPlatform,
  FileModeApplier applyFileMode,
  UpdateCancellationToken? cancellationToken,
) async {
  if (permissionsByMode.isEmpty ||
      targetPlatform == "windows" ||
      Platform.isWindows) {
    return;
  }

  for (final entry in permissionsByMode.entries) {
    for (final paths in _chunks(entry.value, 200)) {
      cancellationToken?.throwIfCancelled();
      await applyFileMode(entry.key, paths, cancellationToken);
      cancellationToken?.throwIfCancelled();
    }
  }
}

/// Applies modes with the package's standalone process fallback.
Future<void> defaultFileModeApplier(
  int mode,
  List<String> paths,
  UpdateCancellationToken? cancellationToken,
) async {
  if (Platform.isWindows) {
    return;
  }
  cancellationToken?.throwIfCancelled();
  final modeText = mode.toRadixString(8).padLeft(3, "0");
  final result = await defaultProcessRunner("chmod", [modeText, ...paths]);
  cancellationToken?.throwIfCancelled();
  if (result.exitCode != 0) {
    throw FileSystemException(
      "Unable to apply zip entry permissions: chmod $modeText "
      "${result.stderr}",
      paths.first,
    );
  }
}

Iterable<List<T>> _chunks<T>(List<T> values, int size) sync* {
  for (var start = 0; start < values.length; start += size) {
    final end = start + size > values.length ? values.length : start + size;
    yield values.sublist(start, end);
  }
}
