part of 'mobile_codex_chat_screen.dart';

class const _MobileWorkspaceFileViewer({
  required final MobileCodexWorkspaceClient client,
  required final String workspaceId,
  required final String? cwd,
  required final MobileCodexWorkspaceLinkTarget target,
  required final bool promptAttachment,
  final bool fallbackToPromptAttachment = false,
}) extends StatefulWidget {
  @override
  State<_MobileWorkspaceFileViewer> createState() =>
      _MobileWorkspaceFileViewerState();
}

class _MobileWorkspaceFileViewerState
    extends State<_MobileWorkspaceFileViewer> {
  final ScrollController _fileScroll = ScrollController();
  final GlobalKey _targetLineKey = GlobalKey();
  File? _rasterFile;
  var _loadedPreviewBytes = 0;
  final List<String> _completedLines = <String>[];
  List<int> _utf8Carry = const <int>[];
  String _lineRemainder = '';
  List<String> _lines = const <String>[];
  MobileWorkspaceFileRange? _range;
  Object? _error;
  var _loading = false;
  var _sharing = false;
  var _targetScrollAttempts = 0;
  var _targetScrollScheduled = false;
  late bool _usePromptAttachment = widget.promptAttachment;

  String get _displayName {
    final candidate = widget.target.displayName?.trim();
    return candidate == null || candidate.isEmpty
        ? _mobileBaseName(widget.target.path)
        : _mobileBaseName(candidate);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _fileScroll.dispose();
    final rasterFile = _rasterFile;
    if (rasterFile != null) unawaited(_deleteRasterPreview(rasterFile));
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading ||
        _sharing ||
        (_range != null && _range!.nextOffset >= _range!.totalBytes) ||
        _loadedPreviewBytes >= maxMobileWorkspacePreviewBytes) {
      return;
    }
    setState(() => _loading = true);
    IOSink? rasterSink;
    var rasterFile = _rasterFile;
    try {
      var next = _range;
      final textChunks = <List<int>>[];
      var pendingLineBreaks = 0;
      do {
        final requestedOffset = next?.nextOffset ?? 0;
        next = await _readRange(requestedOffset);
        if (next.offset != requestedOffset ||
            (next.totalBytes > requestedOffset &&
                next.nextOffset <= requestedOffset)) {
          throw StateError('The remote file preview did not advance.');
        }
        final rasterPreview =
            !next.isText &&
            mobileCodexCanRasterPreviewMime(next.mimeType) &&
            next.totalBytes <= maxMobileWorkspacePreviewBytes;
        if (rasterPreview) {
          rasterFile ??= await _createRasterPreviewFile();
          rasterSink ??= rasterFile.openWrite(
            mode: _loadedPreviewBytes == 0
                ? FileMode.writeOnly
                : FileMode.writeOnlyAppend,
          );
          rasterSink.add(next.bytes);
          _loadedPreviewBytes = next.nextOffset;
          _range = next;
        }
        if (next.isText) {
          textChunks.add(next.bytes);
          pendingLineBreaks += next.bytes.where((byte) => byte == 0x0a).length;
        } else if (!rasterPreview) {
          _loadedPreviewBytes = next.nextOffset;
          _range = next;
        }
      } while (_shouldContinueAutomatically(
        next,
        _completedLines.length + pendingLineBreaks + 1,
      ));
      await rasterSink?.flush();
      await rasterSink?.close();
      rasterSink = null;
      if (next.isText && textChunks.isNotEmpty) {
        final decoded = await compute(
          decodeMobileCodexTextChunks,
          <String, Object?>{
            'carry': _utf8Carry,
            'remainder': _lineRemainder,
            'chunks': textChunks,
            'flush':
                next.nextOffset >= next.totalBytes ||
                next.nextOffset >= maxMobileWorkspacePreviewBytes,
          },
        );
        _completedLines.addAll((decoded['lines']! as List).cast<String>());
        _utf8Carry = (decoded['carry']! as List).cast<int>();
        _lineRemainder = decoded['remainder']! as String;
        _loadedPreviewBytes = next.nextOffset;
        _range = next;
      }
      if (!mounted) {
        if (_rasterFile == null && rasterFile != null) {
          await _deleteRasterPreview(rasterFile);
        }
        return;
      }
      setState(() {
        _lines = next?.isText == true
            ? <String>[..._completedLines, _lineRemainder]
            : const <String>[];
        _rasterFile = rasterFile;
        _loading = false;
        _error = null;
      });
      _scheduleTargetLineScroll();
    } on Object catch (error, stackTrace) {
      await rasterSink?.close();
      _MobileCodexChatScreenState._logger.warning(
        'Could not load Codex file preview.',
        error,
        stackTrace,
      );
      if (!mounted) {
        if (_rasterFile == null && rasterFile != null) {
          await _deleteRasterPreview(rasterFile);
        }
        return;
      }
      setState(() {
        _rasterFile = rasterFile;
        _loading = false;
        _error = error;
      });
    }
  }

  Future<File> _createRasterPreviewFile() async {
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'alera-codex-preview'),
    );
    await directory.create(recursive: true);
    return File(
      p.join(
        directory.path,
        '${DateTime.now().microsecondsSinceEpoch}-$_displayName',
      ),
    );
  }

  Future<void> _deleteRasterPreview(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object catch (error, stackTrace) {
      _MobileCodexChatScreenState._logger.fine(
        'Could not delete a temporary Codex image preview.',
        error,
        stackTrace,
      );
    }
  }

  void _scheduleTargetLineScroll() {
    final line = widget.target.line;
    if (line == null || line <= 0 || line > _lines.length) return;
    if (_targetScrollScheduled || _targetScrollAttempts >= 3) return;
    _targetScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _targetScrollScheduled = false;
      if (!mounted || !_fileScroll.hasClients) return;
      final targetContext = _targetLineKey.currentContext;
      if (targetContext != null) {
        _targetScrollAttempts = 3;
        unawaited(
          Scrollable.ensureVisible(
            targetContext,
            alignment: 0.35,
            duration: AleraTokens.durationMid,
            curve: Curves.easeOut,
          ),
        );
        return;
      }
      _targetScrollAttempts += 1;
      final fraction = (line - 1) / (_lines.length - 1).clamp(1, _lines.length);
      _fileScroll.jumpTo(
        (_fileScroll.position.maxScrollExtent * fraction).clamp(
          0,
          _fileScroll.position.maxScrollExtent,
        ),
      );
      _scheduleTargetLineScroll();
    });
  }

  Future<MobileWorkspaceFileRange> _readRange(int offset) async {
    if (_usePromptAttachment) {
      return widget.client.readPromptAttachment(
        path: widget.target.path,
        offset: offset,
      );
    }
    try {
      return await widget.client.readWorkspaceFile(
        workspaceId: widget.workspaceId,
        relativePath: widget.target.path,
        cwd: widget.cwd,
        offset: offset,
      );
    } on Object {
      if (!widget.fallbackToPromptAttachment || offset != 0) rethrow;
      _usePromptAttachment = true;
      return widget.client.readPromptAttachment(
        path: widget.target.path,
        offset: offset,
      );
    }
  }

  bool _shouldContinueAutomatically(
    MobileWorkspaceFileRange range,
    int projectedLineCount,
  ) {
    if (range.nextOffset >= range.totalBytes ||
        range.nextOffset >= maxMobileWorkspacePreviewBytes) {
      return false;
    }
    final targetLine = widget.target.line;
    if (targetLine != null && projectedLineCount < targetLine) return true;
    return mobileCodexCanRasterPreviewMime(range.mimeType) &&
        range.totalBytes <= maxMobileWorkspacePreviewBytes;
  }

  Future<void> _shareFile(BuildContext shareContext) async {
    final range = _range;
    if (_sharing ||
        _loading ||
        range == null ||
        !mobileWorkspaceFileCanShare(range.totalBytes)) {
      return;
    }
    final sharePositionOrigin = mobileCodexSharePositionOrigin(shareContext);
    setState(() {
      _sharing = true;
    });
    File? temporaryFile;
    IOSink? sink;
    try {
      final directory = Directory(
        p.join((await getTemporaryDirectory()).path, 'alera-codex-share'),
      );
      await directory.create(recursive: true);
      temporaryFile = File(
        p.join(
          directory.path,
          '${DateTime.now().microsecondsSinceEpoch}-$_displayName',
        ),
      );
      sink = temporaryFile.openWrite();
      var offset = 0;
      var mimeType = range.mimeType;
      while (offset < range.totalBytes) {
        final chunk = await _readRange(offset);
        if (chunk.offset != offset || chunk.nextOffset <= offset) {
          throw StateError('The remote file download did not advance.');
        }
        sink.add(chunk.bytes);
        offset = chunk.nextOffset;
        mimeType = chunk.mimeType;
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile(temporaryFile.path, name: _displayName, mimeType: mimeType),
          ],
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    } on Object catch (error, stackTrace) {
      _MobileCodexChatScreenState._logger.warning(
        'Could not share Codex file preview.',
        error,
        stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not share file.')));
      }
    } finally {
      try {
        await sink?.close();
        if (temporaryFile != null && await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      } on Object catch (error, stackTrace) {
        _MobileCodexChatScreenState._logger.warning(
          'Could not clean up shared Codex file preview.',
          error,
          stackTrace,
        );
      } finally {
        if (mounted) setState(() => _sharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => _MobileWorkspaceFileViewerView(
    displayName: _displayName,
    range: _range,
    loading: _loading,
    sharing: _sharing,
    onShare: _shareFile,
    body: _MobileWorkspaceFileViewerBody(
      range: _range,
      error: _error,
      rasterFile: _rasterFile,
      lines: _lines,
      targetLine: widget.target.line,
      loadedPreviewBytes: _loadedPreviewBytes,
      loading: _loading,
      sharing: _sharing,
      scrollController: _fileScroll,
      targetLineKey: _targetLineKey,
      onLoadMore: _load,
    ),
  );
}
