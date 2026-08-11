import 'package:alera_mobile/src/core/json_payload_fields.dart';

const int maxMobileWorkspaceFileRangeBytes = 256 * 1024;
const int maxMobileWorkspacePreviewBytes = 32 * 1024 * 1024;
const int maxMobileWorkspaceShareBytes = 256 * 1024 * 1024;
const int maxPromptFileBytes = 32 * 1024 * 1024;
const int maxPromptFileChunkBytes = 256 * 1024;

class MobileWorkspaceQuickOpenSession {
  const MobileWorkspaceQuickOpenSession({
    required this.id,
    required this.indexedFileCount,
  });

  final String id;
  final int indexedFileCount;

  factory MobileWorkspaceQuickOpenSession.fromJson(Map<String, Object?> json) =>
      MobileWorkspaceQuickOpenSession(
        id: json.requiredString('sessionId'),
        indexedFileCount: json['indexedFileCount'] is int
            ? json['indexedFileCount']! as int
            : 0,
      );
}

class MobileWorkspaceQuickOpenMatch {
  const MobileWorkspaceQuickOpenMatch({
    required this.relativePath,
    required this.score,
  });

  final String relativePath;
  final int score;

  factory MobileWorkspaceQuickOpenMatch.fromJson(Map<String, Object?> json) =>
      MobileWorkspaceQuickOpenMatch(
        relativePath: json.requiredString('relativePath'),
        score: json['score'] is int ? json['score']! as int : 0,
      );
}

class MobileCodexSavedPrompt {
  const MobileCodexSavedPrompt({
    required this.name,
    required this.description,
    required this.body,
    required this.scope,
    this.argumentHint,
  });

  final String name;
  final String description;
  final String body;
  final String scope;
  final String? argumentHint;

  factory MobileCodexSavedPrompt.fromJson(Map<String, Object?> json) =>
      MobileCodexSavedPrompt(
        name: json.requiredString('name'),
        description: json.requiredString('description'),
        body: json['body'] is String
            ? json['body']! as String
            : throw const FormatException('body is required'),
        scope: json.requiredString('scope'),
        argumentHint: json.optionalString('argumentHint'),
      );
}

class MobileWorkspaceFileRange {
  const MobileWorkspaceFileRange({
    required this.relativePath,
    required this.offset,
    required this.nextOffset,
    required this.totalBytes,
    required this.mimeType,
    required this.isText,
    required this.bytes,
  });

  final String relativePath;
  final int offset;
  final int nextOffset;
  final int totalBytes;
  final String mimeType;
  final bool isText;
  final List<int> bytes;
}

bool mobileWorkspaceFileCanShare(int totalBytes) =>
    totalBytes >= 0 && totalBytes <= maxMobileWorkspaceShareBytes;

class PromptFileUploadResult {
  const PromptFileUploadResult({required this.hostPath});

  final String hostPath;

  factory PromptFileUploadResult.fromJson(Map<String, Object?> json) =>
      PromptFileUploadResult(hostPath: json.requiredString('path'));
}
