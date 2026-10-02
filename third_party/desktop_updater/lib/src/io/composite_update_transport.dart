import "dart:async";
import "dart:io";

import "package:desktop_updater/src/core/update_cancellation.dart";
import "package:desktop_updater/src/io/file_update_transport.dart";
import "package:desktop_updater/src/io/http_update_transport.dart";
import "package:desktop_updater/src/io/update_transport.dart";

class CompositeUpdateTransport
    implements UpdateTransport, CancellableUpdateTransport {
  CompositeUpdateTransport({
    HttpUpdateTransport? httpTransport,
    UpdateRequestHeadersProvider? requestHeadersProvider,
    FileUpdateTransport fileTransport = const FileUpdateTransport(),
  })  : _httpTransport = httpTransport ??
            HttpUpdateTransport(requestHeadersProvider: requestHeadersProvider),
        _fileTransport = fileTransport;

  final HttpUpdateTransport _httpTransport;
  final FileUpdateTransport _fileTransport;
  _ActiveDownload? _activeDownload;

  @override
  Future<void> download(
    Uri source,
    File destination, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    Duration? timeout,
  }) {
    if (source.scheme == "http" || source.scheme == "https") {
      return _downloadHttp(
        source,
        destination,
        onProgress: onProgress,
        timeout: timeout,
      );
    }
    if (source.scheme == "file") {
      return _downloadFile(
        source,
        destination,
        onProgress: onProgress,
        timeout: timeout,
      );
    }
    throw UnsupportedError("Unsupported update URL scheme: ${source.scheme}");
  }

  void close() {
    _httpTransport.close();
  }

  /// Aborts the active HTTP request or local-file copy.
  @override
  Future<void> cancel() async {
    final active = _activeDownload;
    if (active == null) {
      return;
    }

    active.cancelRequested = true;
    if (active.fileOperation == null) {
      active.transportCancellation ??= _cancelActive(active);
      await active.transportCancellation;
      return;
    }
    active.fileOperation!.cancel();
    active.transportCancellation ??= _cancelActive(active);
    await active.transportCancellation;
  }

  Future<void> _downloadFile(
    Uri source,
    File destination, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    Duration? timeout,
  }) {
    if (_activeDownload != null) {
      return Future<void>.error(
        StateError("An update download is already in progress."),
      );
    }

    final operation = _FileDownloadOperation();
    final active = _ActiveDownload.file(operation);
    _activeDownload = active;
    return _runFileDownload(
      active,
      source,
      destination,
      onProgress: onProgress,
      timeout: timeout,
    );
  }

  Future<void> _runFileDownload(
    _ActiveDownload active,
    Uri source,
    File destination, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    Duration? timeout,
  }) async {
    try {
      if (active.cancelRequested) {
        throw const UpdateCancelledException();
      }
      await _fileTransport.downloadCancellable(
        source,
        destination,
        onProgress: onProgress,
        timeout: timeout,
        isCancelled: () => active.fileOperation!.isCancelled,
      );
    } finally {
      if (identical(_activeDownload, active)) {
        _activeDownload = null;
      }
      active.complete();
    }
  }

  Future<void> _downloadHttp(
    Uri source,
    File destination, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    Duration? timeout,
  }) {
    if (_activeDownload != null) {
      return Future<void>.error(
        StateError("An update download is already in progress."),
      );
    }

    final active = _ActiveDownload.http();
    _activeDownload = active;
    return _runHttpDownload(
      active,
      source,
      destination,
      onProgress: onProgress,
      timeout: timeout,
    );
  }

  Future<void> _runHttpDownload(
    _ActiveDownload active,
    Uri source,
    File destination, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    Duration? timeout,
  }) async {
    try {
      if (active.cancelRequested) {
        throw const UpdateCancelledException();
      }
      await _httpTransport.download(
        source,
        destination,
        onProgress: onProgress,
        timeout: timeout,
      );
    } finally {
      if (identical(_activeDownload, active)) {
        _activeDownload = null;
      }
      active.complete();
    }
  }

  Future<void> _cancelActive(_ActiveDownload active) async {
    if (active.fileOperation == null) {
      await _httpTransport.cancel();
      return;
    }
    await active.completed;
  }
}

class _ActiveDownload {
  _ActiveDownload.http() : fileOperation = null;

  _ActiveDownload.file(this.fileOperation);

  final _FileDownloadOperation? fileOperation;
  final Completer<void> _completed = Completer<void>();
  Future<void>? transportCancellation;
  bool cancelRequested = false;

  Future<void> get completed => _completed.future;

  void complete() {
    if (!_completed.isCompleted) {
      _completed.complete();
    }
  }
}

class _FileDownloadOperation {
  bool isCancelled = false;

  void cancel() {
    isCancelled = true;
  }
}
