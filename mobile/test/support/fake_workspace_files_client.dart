import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/mobile_codex_workspace.dart';
import 'package:alera_mobile/src/features/runtime/domain/prompt_image_upload.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';

/// Every attachment source a prompt can draw from: the two uploads and the
/// workspace-files surface. The runtime client implements them alongside the
/// workspace one, so the fakes do too, because New Workspace and the terminal
/// reach all of them through a single `workspaceClientProvider`.
mixin FakeWorkspaceFilesClient implements MobileCodexWorkspaceClient {
  /// Provided by the host fake, which records every request for assertions.
  List<String> get calls;

  Object? promptImageUploadError;
  int? failPromptImageUploadAt;
  final List<List<int>> promptImageChunks = <List<int>>[];
  int _promptImageUploads = 0;

  // Declared by MobileWorkspaceClient, which the host fake implements; the
  // mixin only carries the behaviour.
  Future<PromptImageUploadResult> uploadPromptImage({
    required String format,
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  }) async {
    calls.add('uploadPromptImage $format $sizeBytes');
    if (failPromptImageUploadAt != null) {
      if (failPromptImageUploadAt == _promptImageUploads + 1) {
        throw promptImageUploadError ??
            StateError('prompt image upload failed');
      }
    } else if (promptImageUploadError != null) {
      throw promptImageUploadError!;
    }
    await for (final chunk in openRead()) {
      promptImageChunks.add(List<int>.from(chunk));
    }
    _promptImageUploads += 1;
    return PromptImageUploadResult(
      hostPath: '/runtime/prompt-images/upload-$_promptImageUploads.$format',
    );
  }

  List<String> workspaceFiles = const <String>[];
  bool promptFileUploadSupported = false;
  Object? promptFileUploadError;
  final List<List<int>> promptFileChunks = <List<int>>[];
  final List<MobileWorkspaceQuickOpenSession> stoppedQuickOpenSessions =
      <MobileWorkspaceQuickOpenSession>[];
  int _promptFileUploads = 0;

  @override
  bool get supportsCodexWorkspaceFiles => workspaceFiles.isNotEmpty;

  @override
  bool get supportsPromptFileUpload => promptFileUploadSupported;

  @override
  bool get supportsPromptAttachmentRead => false;

  @override
  Future<MobileWorkspaceQuickOpenSession> startWorkspaceQuickOpen(
    String workspaceId, {
    String? cwd,
  }) async {
    calls.add('startWorkspaceQuickOpen $workspaceId');
    return MobileWorkspaceQuickOpenSession(
      id: 'quick-open-$workspaceId',
      indexedFileCount: workspaceFiles.length,
    );
  }

  @override
  Future<List<MobileWorkspaceQuickOpenMatch>> searchWorkspaceQuickOpen(
    MobileWorkspaceQuickOpenSession session,
    String query, {
    int limit = 20,
  }) async => workspaceFiles
      .where((path) => path.toLowerCase().contains(query.toLowerCase()))
      .take(limit)
      .map(
        (path) => MobileWorkspaceQuickOpenMatch(relativePath: path, score: 1),
      )
      .toList(growable: false);

  @override
  Future<void> stopWorkspaceQuickOpen(
    MobileWorkspaceQuickOpenSession session,
  ) async => stoppedQuickOpenSessions.add(session);

  @override
  Future<MobileWorkspaceFileRange> readWorkspaceFile({
    required String workspaceId,
    required String relativePath,
    String? cwd,
    int offset = 0,
    int length = maxMobileWorkspaceFileRangeBytes,
  }) async => throw UnimplementedError();

  @override
  Future<MobileWorkspaceFileRange> readPromptAttachment({
    required String path,
    int offset = 0,
    int length = maxMobileWorkspaceFileRangeBytes,
  }) async => throw UnimplementedError();

  @override
  Future<PromptFileUploadResult> uploadPromptFile({
    required String name,
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  }) async {
    calls.add('uploadPromptFile $name $sizeBytes');
    if (promptFileUploadError != null) {
      throw promptFileUploadError!;
    }
    await for (final chunk in openRead()) {
      promptFileChunks.add(List<int>.from(chunk));
    }
    _promptFileUploads += 1;
    return PromptFileUploadResult(
      hostPath: '/runtime/prompt-files/upload-$_promptFileUploads-$name',
    );
  }
}
