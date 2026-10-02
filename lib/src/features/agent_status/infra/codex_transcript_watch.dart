part of 'codex_transcript_status_watcher.dart';

class _CodexTranscriptWatch({
  required final AgentStatusSink _statusSink,
  required final String terminalSessionId,
  required final String workspaceId,
  required final String tabId,
  required final String transcriptPath,
  required final String? turnId,
  required final Duration watchdogInterval,
  required final AppForeground appForeground,
}) {
  final Map<String, String> _pendingToolsByCallId = <String, String>{};
  final Set<String> _emittedCallIds = <String>{};
  StreamSubscription<FileSystemEvent>? _subscription;
  StreamSubscription<bool>? _foregroundSubscription;
  Timer? _watchdogTimer;
  Timer? _pollTimer;

  /// Whether polling was the active strategy when the app went to the
  /// background, so returning restores the same one rather than upgrading a
  /// degraded watch back to a file-event watch that already failed.
  var _polling = false;
  var _offset = 0;
  var _partialLine = '';
  var _armed = false;
  var _initialScan = true;
  var _disposed = false;
  var _lifecycleGeneration = 0;
  var _scanning = false;
  var _scanAgain = false;
  var _scanAgainAllowsBackground = false;
  Completer<void>? _activeScan;
  ByteConversionSink? _utf8Decoder;

  void start() {
    _foregroundSubscription = appForeground.changes.listen(_applyForeground);
    final file = File(transcriptPath);
    try {
      final length = file.existsSync() ? file.lengthSync() : 0;
      _offset = math.max(0, length - _initialTranscriptScanBytes);
      _subscription = file
          .watch(
            events:
                FileSystemEvent.create |
                FileSystemEvent.modify |
                FileSystemEvent.move,
          )
          .listen(
            (_) {
              _armWatchdog();
              _scheduleScan(allowsBackground: true);
            },
            onError: (_) => _enablePolling(),
            onDone: _enablePolling,
          );
      _armWatchdog();
    } catch (_) {
      // coverage:ignore-start
      // File watch setup can fail on platform/filesystem races; scan polling
      // still handles the transcript and is covered by watcher tests.
      _offset = 0;
      _enablePolling();
      // coverage:ignore-end
    }
    _scheduleScan(allowsBackground: true);
  }

  Future<void> scan({bool allowsBackground = true}) async {
    if (_disposed) {
      return;
    }
    final lifecycleGeneration = _lifecycleGeneration;
    if (_scanning) {
      _scanAgain = true;
      _scanAgainAllowsBackground |= allowsBackground;
      await _activeScan?.future;
      return;
    }
    _scanning = true;
    final activeScan = Completer<void>();
    _activeScan = activeScan;
    try {
      var scanAllowsBackground = allowsBackground;
      do {
        _scanAgain = false;
        _scanAgainAllowsBackground = false;
        await _scanOnce(
          allowsBackground: scanAllowsBackground,
          lifecycleGeneration: lifecycleGeneration,
        );
        if (!_isCurrentGeneration(lifecycleGeneration)) {
          break;
        }
        scanAllowsBackground = _scanAgainAllowsBackground;
      } while (_scanAgain && _isCurrentGeneration(lifecycleGeneration));
    } finally {
      _scanning = false;
      _activeScan = null;
      activeScan.complete();
    }
  }

  void dispose() {
    _disposed = true;
    _lifecycleGeneration++;
    unawaited(_subscription?.cancel());
    unawaited(_foregroundSubscription?.cancel());
    _watchdogTimer?.cancel();
    _pollTimer?.cancel();
    _subscription = null;
    _foregroundSubscription = null;
    _watchdogTimer = null;
    _pollTimer = null;
  }

  /// Park the timers while the app is hidden, and catch up on return.
  ///
  /// This is the one poller in the app that scales with how many agents are
  /// running: a stat plus an incremental read per transcript, every interval,
  /// whether or not anyone can see the status it produces.
  ///
  /// The file watch keeps running while parked. It is event driven, so it costs
  /// nothing idle, and leaving it subscribed means a transcript that changes
  /// while hidden is still noticed. Only the safety net stops. Nothing is lost
  /// either way: scanning resumes from the same byte offset, so returning to
  /// the foreground reads whatever accumulated.
  void _applyForeground(bool isForeground) {
    if (_disposed) {
      return;
    }
    if (!isForeground) {
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    if (_polling) {
      _startPollTimer();
    } else {
      _armWatchdog();
    }
    _scheduleScan(allowsBackground: true);
  }

  void _armWatchdog() {
    if (_disposed || _polling || !appForeground.isForeground) {
      return;
    }
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(watchdogInterval, () {
      _scheduleScan(allowsBackground: false);
      _armWatchdog();
    });
  }

  void _enablePolling() {
    if (_disposed || _polling) {
      return;
    }
    _polling = true;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _startPollTimer();
  }

  void _startPollTimer() {
    if (_disposed || _pollTimer != null || !appForeground.isForeground) {
      return;
    }
    _pollTimer = Timer.periodic(
      watchdogInterval,
      (_) => _scheduleScan(allowsBackground: false),
    );
  }

  void _scheduleScan({required bool allowsBackground}) {
    unawaited(scan(allowsBackground: allowsBackground));
  }

  Future<void> _scanOnce({
    required bool allowsBackground,
    required int lifecycleGeneration,
  }) async {
    if (!_isCurrentGeneration(lifecycleGeneration) ||
        (!allowsBackground && !appForeground.isForeground)) {
      return;
    }
    final file = File(transcriptPath);
    int length;
    try {
      length = await file.length();
    } catch (_) {
      return;
    }
    if (!_isCurrentGeneration(lifecycleGeneration) ||
        (!allowsBackground && !appForeground.isForeground)) {
      return;
    }
    if (length < _offset) {
      _resetForRecreatedTranscript();
    }
    if (length <= _offset) {
      _finishInitialScanIfNeeded();
      return;
    }

    RandomAccessFile? handle;
    try {
      handle = await file.open();
      if (!_isCurrentGeneration(lifecycleGeneration)) {
        return;
      }
      await handle.setPosition(_offset);
      if (!_isCurrentGeneration(lifecycleGeneration)) {
        return;
      }
      final scanEnd = math.min(length, _offset + _maxTranscriptScanBytes);
      while (_offset < scanEnd) {
        if (!_isCurrentGeneration(lifecycleGeneration) ||
            (!allowsBackground && !appForeground.isForeground)) {
          return;
        }
        final bytes = await handle.read(
          math.min(_transcriptReadChunkBytes, scanEnd - _offset),
        );
        if (bytes.isEmpty) {
          break;
        }
        if (!_isCurrentGeneration(lifecycleGeneration) ||
            (!allowsBackground && !appForeground.isForeground)) {
          return;
        }
        _offset += bytes.length;
        _decodeBytes(bytes, lifecycleGeneration: lifecycleGeneration);
      }
    } catch (_) {
      return;
    } finally {
      await handle?.close();
      if (_isCurrentGeneration(lifecycleGeneration)) {
        _finishInitialScanIfNeeded();
      }
    }
  }

  void _decodeBytes(List<int> bytes, {required int lifecycleGeneration}) {
    if (!_isCurrentGeneration(lifecycleGeneration)) {
      return;
    }
    (_utf8Decoder ??= const Utf8Decoder(allowMalformed: true)
            .startChunkedConversion(
              StringConversionSink.from(
                _CodexTranscriptTextSink(
                  (text) => _processTextChunk(
                    text,
                    lifecycleGeneration: lifecycleGeneration,
                  ),
                ),
              ),
            ))
        .add(bytes);
  }

  bool _isCurrentGeneration(int lifecycleGeneration) {
    return !_disposed && _lifecycleGeneration == lifecycleGeneration;
  }

  void _resetForRecreatedTranscript() {
    _offset = 0;
    _partialLine = '';
    _utf8Decoder = null;
    _pendingToolsByCallId.clear();
    _emittedCallIds.clear();
    _armed = false;
    _initialScan = true;
  }

  void _processTextChunk(String text, {required int lifecycleGeneration}) {
    if (!_isCurrentGeneration(lifecycleGeneration)) {
      return;
    }
    final combined = _partialLine + text;
    final lines = combined.split('\n');
    _partialLine = combined.endsWith('\n') ? '' : lines.removeLast();
    if (_partialLine.length > _maxTranscriptLineCharacters) {
      // A malformed or hostile JSONL record must not grow across scans while
      // waiting for its newline. Drop it and resume at the next record.
      _partialLine = '';
    }
    for (final rawLine in lines) {
      if (!_isCurrentGeneration(lifecycleGeneration)) {
        return;
      }
      if (rawLine.length > _maxTranscriptLineCharacters) {
        continue;
      }
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      _processLine(line, lifecycleGeneration: lifecycleGeneration);
    }
  }

  void _finishInitialScanIfNeeded() {
    if (!_initialScan) {
      return;
    }
    _initialScan = false;
    _armed = true;
  }
}

final class _CodexTranscriptTextSink implements Sink<String> {
  const _CodexTranscriptTextSink(this._onChunk);

  final void Function(String) _onChunk;

  @override
  void add(String chunk) => _onChunk(chunk);

  @override
  void close() {}
}

String? _hookEventName(AgentHookEvent event) {
  return event.hookEventName ??
      _readString(event.payload, const <String>[
        'hook_event_name',
        'hookEventName',
      ]);
}

const int _initialTranscriptScanBytes = 256 * 1024;
const int _maxTranscriptScanBytes = 1024 * 1024;
const int _transcriptReadChunkBytes = 64 * 1024;
const int _maxTranscriptLineCharacters = 1024 * 1024;
