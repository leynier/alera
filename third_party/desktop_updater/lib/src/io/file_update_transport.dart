import "dart:async";
import "dart:io";

import "package:desktop_updater/src/core/update_cancellation.dart";
import "package:desktop_updater/src/io/update_transport.dart";

class FileUpdateTransport implements UpdateTransport {
  const FileUpdateTransport();

  @override
  Future<void> download(
    Uri source,
    File destination, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    Duration? timeout,
  }) async {
    return downloadCancellable(
      source,
      destination,
      onProgress: onProgress,
      timeout: timeout,
      isCancelled: () => false,
    );
  }

  /// Internal cancellation-aware entry point used by composite transports.
  ///
  /// The public [download] contract remains unchanged for direct consumers.
  Future<void> downloadCancellable(
    Uri source,
    File destination, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    Duration? timeout,
    required bool Function() isCancelled,
  }) async {
    if (source.scheme != "file") {
      throw UnsupportedError("File transport cannot fetch ${source.scheme}.");
    }

    final sourceFile = File(source.toFilePath(windows: Platform.isWindows));
    if (!await sourceFile.exists()) {
      throw FileSystemException("Update file not found", sourceFile.path);
    }

    _throwIfCancelled(isCancelled);
    await destination.parent.create(recursive: true);
    final partial = File("${destination.path}.part");
    if (await partial.exists()) {
      await partial.delete();
    }

    try {
      _throwIfCancelled(isCancelled);
      await _copy(
        sourceFile,
        partial,
        onProgress: onProgress,
        isCancelled: isCancelled,
      ).timeout(timeout ?? const Duration(days: 365));

      _throwIfCancelled(isCancelled);
      await _replaceDestination(
        partial,
        destination,
        isCancelled: isCancelled,
      );
    } catch (_) {
      if (await partial.exists()) {
        await partial.delete();
      }
      rethrow;
    }
  }
}

Future<void> _copy(
  File source,
  File destination, {
  void Function(int receivedBytes, int? totalBytes)? onProgress,
  required bool Function() isCancelled,
}) async {
  _throwIfCancelled(isCancelled);
  final totalBytes = await source.length();
  final sink = destination.openWrite();
  var receivedBytes = 0;

  try {
    await for (final chunk in source.openRead()) {
      _throwIfCancelled(isCancelled);
      receivedBytes += chunk.length;
      sink.add(chunk);
      _throwIfCancelled(isCancelled);
      onProgress?.call(receivedBytes, totalBytes);
    }
  } finally {
    await sink.close();
  }
}

Future<void> _replaceDestination(
  File partial,
  File destination, {
  required bool Function() isCancelled,
}) async {
  File? previous;
  try {
    _throwIfCancelled(isCancelled);
    previous = await _moveDestinationAside(destination);
    _throwIfCancelled(isCancelled);
    await partial.rename(destination.path);
    if (isCancelled()) {
      await _removeFileIfPresent(destination);
      await _restorePrevious(previous, destination);
      throw const UpdateCancelledException();
    }
    await _removeFileIfPresent(previous);
  } catch (_) {
    await _removeFileIfPresent(partial);
    await _restorePrevious(previous, destination);
    rethrow;
  }
}

Future<File?> _moveDestinationAside(File destination) async {
  if (!await destination.exists()) {
    return null;
  }

  final previous = File(
    "${destination.path}.previous."
    "${DateTime.now().microsecondsSinceEpoch}.${++_previousFileSerial}",
  );
  await destination.rename(previous.path);
  return previous;
}

Future<void> _restorePrevious(File? previous, File destination) async {
  if (previous == null || !await previous.exists()) {
    return;
  }
  if (await destination.exists()) {
    await destination.delete();
  }
  await previous.rename(destination.path);
}

Future<void> _removeFileIfPresent(File? file) async {
  if (file != null && await file.exists()) {
    await file.delete();
  }
}

void _throwIfCancelled(bool Function() isCancelled) {
  if (isCancelled()) {
    throw const UpdateCancelledException();
  }
}

var _previousFileSerial = 0;
