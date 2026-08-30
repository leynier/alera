part of 'mobile_runtime_client.dart';

const Duration _workspaceQuickOpenIndexTimeout = Duration(minutes: 5);

mixin MobileRuntimeCodexWorkspaceRequests {
  Set<String> get runtimeCapabilities;

  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  bool get supportsCodexWorkspaceFiles =>
      runtimeCapabilities.contains(mobileCodexWorkspaceFilesCapability);

  bool get supportsPromptFileUpload =>
      runtimeCapabilities.contains(mobilePromptFileUploadCapability);

  bool get supportsPromptAttachmentRead =>
      runtimeCapabilities.contains(mobilePromptAttachmentReadCapability);

  Future<MobileWorkspaceQuickOpenSession> startWorkspaceQuickOpen(
    String workspaceId, {
    String? cwd,
  }) async {
    _requireWorkspaceFiles();
    final normalizedCwd = cwd?.trim();
    return MobileWorkspaceQuickOpenSession.fromJson(
      await requestMap('mobile.workspaceQuickOpen.start', <String, Object?>{
        'workspaceId': workspaceId,
        if (normalizedCwd != null && normalizedCwd.isNotEmpty)
          'cwd': normalizedCwd,
      }, _workspaceQuickOpenIndexTimeout),
    );
  }

  Future<List<MobileWorkspaceQuickOpenMatch>> searchWorkspaceQuickOpen(
    MobileWorkspaceQuickOpenSession session,
    String query, {
    int limit = 20,
  }) async {
    _requireWorkspaceFiles();
    final payload =
        await requestMap('mobile.workspaceQuickOpen.search', <String, Object?>{
          'sessionId': session.id,
          'indexedFileCount': session.indexedFileCount,
          'query': query,
          'limit': limit,
        });
    return <MobileWorkspaceQuickOpenMatch>[
      if (payload['items'] is List)
        for (final item in payload['items']! as List)
          if (item is Map)
            MobileWorkspaceQuickOpenMatch.fromJson(
              Map<String, Object?>.from(item),
            ),
    ];
  }

  Future<void> stopWorkspaceQuickOpen(
    MobileWorkspaceQuickOpenSession session,
  ) async {
    _requireWorkspaceFiles();
    await request('mobile.workspaceQuickOpen.stop', <String, Object?>{
      'sessionId': session.id,
    });
  }

  Future<List<MobileCodexSavedPrompt>> listCodexSavedPrompts(
    String workspaceId, {
    String? cwd,
  }) async {
    _requireWorkspaceFiles();
    final normalizedCwd = cwd?.trim();
    final payload =
        await requestMap('mobile.codexSavedPrompts.list', <String, Object?>{
          'workspaceId': workspaceId,
          if (normalizedCwd != null && normalizedCwd.isNotEmpty)
            'cwd': normalizedCwd,
        });
    return <MobileCodexSavedPrompt>[
      if (payload['items'] is List)
        for (final item in payload['items']! as List)
          if (item is Map)
            MobileCodexSavedPrompt.fromJson(Map<String, Object?>.from(item)),
    ];
  }

  Future<MobileWorkspaceFileRange> readWorkspaceFile({
    required String workspaceId,
    required String relativePath,
    String? cwd,
    int offset = 0,
    int length = maxMobileWorkspaceFileRangeBytes,
  }) async {
    _requireWorkspaceFiles();
    final normalizedCwd = cwd?.trim();
    final payload =
        await requestMap('mobile.workspaceFile.read', <String, Object?>{
          'workspaceId': workspaceId,
          'relativePath': relativePath,
          if (normalizedCwd != null && normalizedCwd.isNotEmpty)
            'cwd': normalizedCwd,
          'offset': offset,
          'length': length,
        });
    return MobileWorkspaceFileRange(
      relativePath: payload.requiredString('relativePath'),
      offset: payload['offset']! as int,
      nextOffset: payload['nextOffset']! as int,
      totalBytes: payload['totalBytes']! as int,
      mimeType: payload.requiredString('mimeType'),
      isText: payload['isText'] == true,
      bytes: base64Decode(payload.requiredString('dataBase64')),
    );
  }

  Future<MobileWorkspaceFileRange> readPromptAttachment({
    required String path,
    int offset = 0,
    int length = maxMobileWorkspaceFileRangeBytes,
  }) async {
    if (!supportsPromptAttachmentRead) {
      throw UnsupportedError(
        'Update the paired Alera runtime to preview attachments.',
      );
    }
    final payload = await requestMap(
      'mobile.promptAttachment.read',
      <String, Object?>{'path': path, 'offset': offset, 'length': length},
    );
    return MobileWorkspaceFileRange(
      relativePath: payload.requiredString('relativePath'),
      offset: payload['offset']! as int,
      nextOffset: payload['nextOffset']! as int,
      totalBytes: payload['totalBytes']! as int,
      mimeType: payload.requiredString('mimeType'),
      isText: payload['isText'] == true,
      bytes: base64Decode(payload.requiredString('dataBase64')),
    );
  }

  Future<PromptFileUploadResult> uploadPromptFile({
    required String name,
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  }) async {
    if (!supportsPromptFileUpload) {
      throw UnsupportedError(
        'Update the paired Alera runtime to attach files.',
      );
    }
    if (sizeBytes <= 0 || sizeBytes > maxPromptFileBytes) {
      throw StateError('The selected file must be smaller than 32 MiB.');
    }
    String? uploadId;
    try {
      final started = await requestMap(
        'mobile.promptFile.start',
        <String, Object?>{'name': name, 'sizeBytes': sizeBytes},
      );
      uploadId = started.requiredString('uploadId');
      var offset = 0;
      await for (final bytes in openRead()) {
        for (var start = 0; start < bytes.length;) {
          final end = start + maxPromptFileChunkBytes < bytes.length
              ? start + maxPromptFileChunkBytes
              : bytes.length;
          final chunk = bytes.sublist(start, end);
          final response =
              await requestMap('mobile.promptFile.chunk', <String, Object?>{
                'uploadId': uploadId,
                'offset': offset,
                'dataBase64': base64Encode(chunk),
              });
          offset = response['nextOffset']! as int;
          start = end;
        }
      }
      if (offset != sizeBytes) {
        throw StateError('The selected file could not be read completely.');
      }
      return PromptFileUploadResult.fromJson(
        await requestMap('mobile.promptFile.complete', <String, Object?>{
          'uploadId': uploadId,
        }),
      );
    } on Object {
      if (uploadId != null) {
        try {
          await request('mobile.promptFile.cancel', <String, Object?>{
            'uploadId': uploadId,
          });
        } on Object catch (error, stackTrace) {
          Logger('MobileRuntimeCodexWorkspaceRequests').warning(
            'could not cancel failed prompt file upload',
            error,
            stackTrace,
          );
        }
      }
      rethrow;
    }
  }

  void _requireWorkspaceFiles() {
    if (!supportsCodexWorkspaceFiles) {
      throw UnsupportedError(
        'Update the paired Alera runtime to browse workspace files.',
      );
    }
  }
}
