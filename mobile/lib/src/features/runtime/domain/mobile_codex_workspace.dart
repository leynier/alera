import 'package:alera_mobile/src/core/json_payload_fields.dart';

const int maxMobileWorkspaceFileRangeBytes = 256 * 1024;
const int maxMobileWorkspacePreviewBytes = 32 * 1024 * 1024;
const int maxMobileWorkspaceShareBytes = 256 * 1024 * 1024;
const int maxPromptFileBytes = 32 * 1024 * 1024;
const int maxPromptFileChunkBytes = 256 * 1024;

class const MobileWorkspaceQuickOpenSession({
  required final String id,
  required final int indexedFileCount,
}) {
  factory fromJson(Map<String, Object?> json) =>
      MobileWorkspaceQuickOpenSession(
        id: json.requiredString('sessionId'),
        indexedFileCount: json['indexedFileCount'] is int
            ? json['indexedFileCount']! as int
            : 0,
      );
}

class const MobileWorkspaceQuickOpenMatch({
  required final String relativePath,
  required final int score,
}) {
  factory fromJson(Map<String, Object?> json) => MobileWorkspaceQuickOpenMatch(
    relativePath: json.requiredString('relativePath'),
    score: json['score'] is int ? json['score']! as int : 0,
  );
}

class const MobileCodexSavedPrompt({
  required final String name,
  required final String description,
  required final String body,
  required final String scope,
  final String? argumentHint,
}) {
  factory fromJson(Map<String, Object?> json) => MobileCodexSavedPrompt(
    name: json.requiredString('name'),
    description: json.requiredString('description'),
    body: json['body'] is String
        ? json['body']! as String
        : throw const FormatException('body is required'),
    scope: json.requiredString('scope'),
    argumentHint: json.optionalString('argumentHint'),
  );
}

class const MobileWorkspaceFileRange({
  required final String relativePath,
  required final int offset,
  required final int nextOffset,
  required final int totalBytes,
  required final String mimeType,
  required final bool isText,
  required final List<int> bytes,
});

bool mobileWorkspaceFileCanShare(int totalBytes) =>
    totalBytes >= 0 && totalBytes <= maxMobileWorkspaceShareBytes;

class const PromptFileUploadResult({required final String hostPath}) {
  factory fromJson(Map<String, Object?> json) =>
      PromptFileUploadResult(hostPath: json.requiredString('path'));
}
