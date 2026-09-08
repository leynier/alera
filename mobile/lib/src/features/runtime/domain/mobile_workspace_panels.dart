import 'package:alera_mobile/src/core/json_payload_fields.dart';

export 'package:alera_mobile/src/core/mobile_protocol.dart'
    show
        mobileExplorerCapability,
        mobilePullRequestCapability,
        mobileSourceControlCapability,
        mobileWorkspaceSearchCapability;

class const MobileExplorerEntry({
  required final String relativePath,
  required final String name,
  required final String kind,
  final int size = 0,
  final bool isHidden = false,
  final bool hasChildrenHint = false,
}) {
  bool get isDirectory => kind == 'directory';
  bool get isFile => kind == 'file';

  factory fromJson(Map<String, Object?> json) => MobileExplorerEntry(
    relativePath: json.requiredString('relativePath'),
    name: json.requiredString('name'),
    kind: json.optionalString('kind') ?? 'file',
    size: (json['size'] as num?)?.toInt() ?? 0,
    isHidden: json['isHidden'] == true,
    hasChildrenHint: json['hasChildrenHint'] == true,
  );
}

class const MobileWorkspaceSearchMatch({
  required final String id,
  required final int line,
  required final int column,
  required final int matchLength,
  required final String lineContent,
}) {
  factory fromJson(Map<String, Object?> json) => MobileWorkspaceSearchMatch(
    id: json.requiredString('id'),
    line: (json['line'] as num?)?.toInt() ?? 1,
    column: (json['column'] as num?)?.toInt() ?? 1,
    matchLength: (json['matchLength'] as num?)?.toInt() ?? 0,
    lineContent: json.optionalString('lineContent') ?? '',
  );
}

class const MobileWorkspaceSearchFile({
  required final String relativePath,
  final List<MobileWorkspaceSearchMatch> matches =
      const <MobileWorkspaceSearchMatch>[],
}) {
  factory fromJson(Map<String, Object?> json) => MobileWorkspaceSearchFile(
    relativePath: json.requiredString('relativePath'),
    matches: <MobileWorkspaceSearchMatch>[
      for (final item in json.objectList('matches'))
        if (item is Map)
          MobileWorkspaceSearchMatch.fromJson(Map<String, Object?>.from(item)),
    ],
  );
}

class const MobileWorkspaceSearchResult({
  final List<MobileWorkspaceSearchFile> files =
      const <MobileWorkspaceSearchFile>[],
  final int totalMatches = 0,
  final bool truncated = false,
}) {
  factory fromJson(Map<String, Object?> json) => MobileWorkspaceSearchResult(
    files: <MobileWorkspaceSearchFile>[
      for (final item in json.objectList('files'))
        if (item is Map)
          MobileWorkspaceSearchFile.fromJson(Map<String, Object?>.from(item)),
    ],
    totalMatches: (json['totalMatches'] as num?)?.toInt() ?? 0,
    truncated: json['truncated'] == true,
  );
}

class const MobileGitChange({
  required final String path,
  required final String area,
  required final String status,
  final String? oldPath,
  final int? added,
  final int? removed,
  final bool isBinary = false,
}) {
  factory fromJson(Map<String, Object?> json) => MobileGitChange(
    path: json.requiredString('path'),
    oldPath: json.optionalString('oldPath'),
    area: json.optionalString('area') ?? 'unstaged',
    status: json.optionalString('status') ?? 'modified',
    added: (json['added'] as num?)?.toInt(),
    removed: (json['removed'] as num?)?.toInt(),
    isBinary: json['isBinary'] == true,
  );
}

class const MobileGitStatusSnapshot({
  final bool isRepository = false,
  final String? branch,
  final List<MobileGitChange> entries = const <MobileGitChange>[],
  final bool writable = false,
}) {
  factory fromJson(Map<String, Object?> json) => MobileGitStatusSnapshot(
    isRepository: json['isRepository'] == true,
    branch: json.optionalString('branch'),
    entries: <MobileGitChange>[
      for (final item in json.objectList('entries'))
        if (item is Map)
          MobileGitChange.fromJson(Map<String, Object?>.from(item)),
    ],
    writable: json['writable'] == true,
  );
}

class const MobileGitDiffLine({
  required final String kind,
  required final String text,
}) {
  factory fromJson(Map<String, Object?> json) => MobileGitDiffLine(
    kind: json.optionalString('kind') ?? 'context',
    text: json.optionalString('text') ?? '',
  );
}

class const MobileGitDiffFile({
  required final String path,
  required final String area,
  final bool isBinary = false,
  final bool truncated = false,
  final List<MobileGitDiffLine> lines = const <MobileGitDiffLine>[],
}) {
  factory fromJson(Map<String, Object?> json) => MobileGitDiffFile(
    path: json.requiredString('path'),
    area: json.optionalString('area') ?? 'unstaged',
    isBinary: json['isBinary'] == true,
    truncated: json['truncated'] == true,
    lines: <MobileGitDiffLine>[
      for (final item in json.objectList('lines'))
        if (item is Map)
          MobileGitDiffLine.fromJson(Map<String, Object?>.from(item)),
    ],
  );
}

class const MobilePullRequestCheck({
  required final String name,
  final String state = '',
  final String bucket = '',
  final String? url,
}) {
  factory fromJson(Map<String, Object?> json) => MobilePullRequestCheck(
    name: json.optionalString('name') ?? 'check',
    state: json.optionalString('state') ?? '',
    bucket: json.optionalString('bucket') ?? '',
    url: json.optionalString('url'),
  );
}

class const MobilePullRequestComment({
  required final int id,
  final String? author,
  final String body = '',
  final String? createdAt,
  final String? url,
}) {
  factory fromJson(Map<String, Object?> json) => MobilePullRequestComment(
    id: (json['id'] as num?)?.toInt() ?? 0,
    author: json.optionalString('author'),
    body: json.optionalString('body') ?? '',
    createdAt: json.optionalString('createdAt'),
    url: json.optionalString('url'),
  );
}

class const MobilePullRequestReview({
  required final int number,
  required final String title,
  required final String state,
  required final String url,
  final bool isDraft = false,
  final String? author,
  final String? headRefName,
  final String? baseRefName,
  final String? createdAt,
  final String? mergeable,
  final List<MobilePullRequestCheck> checks = const <MobilePullRequestCheck>[],
  final List<MobilePullRequestComment> comments =
      const <MobilePullRequestComment>[],
}) {
  factory fromJson(Map<String, Object?> json) => MobilePullRequestReview(
    number: (json['number'] as num?)?.toInt() ?? 0,
    title: json.optionalString('title') ?? '',
    state: json.optionalString('state') ?? 'OPEN',
    url: json.optionalString('url') ?? '',
    isDraft: json['isDraft'] == true,
    author: json.optionalString('author'),
    headRefName: json.optionalString('headRefName'),
    baseRefName: json.optionalString('baseRefName'),
    createdAt: json.optionalString('createdAt'),
    mergeable: json.optionalString('mergeable'),
    checks: <MobilePullRequestCheck>[
      for (final item in json.objectList('checks'))
        if (item is Map)
          MobilePullRequestCheck.fromJson(Map<String, Object?>.from(item)),
    ],
    comments: <MobilePullRequestComment>[
      for (final item in json.objectList('comments'))
        if (item is Map)
          MobilePullRequestComment.fromJson(Map<String, Object?>.from(item)),
    ],
  );
}

class const MobilePullRequestSnapshot({
  final String? branch,
  final String? remoteUrl,
  final String? provider,
  final String? authStatus,
  final String? unavailableReason,
  final int? linkedNumber,
  final String? linkedUrl,
  final MobilePullRequestReview? review,
}) {
  factory fromJson(Map<String, Object?> json) {
    final linked = json.mapValue('linkedReview');
    final review = json['review'];
    return MobilePullRequestSnapshot(
      branch: json.optionalString('branch'),
      remoteUrl: json.optionalString('remoteUrl'),
      provider: json.optionalString('provider'),
      authStatus: json.optionalString('authStatus'),
      unavailableReason: json.optionalString('unavailableReason'),
      linkedNumber: (linked['number'] as num?)?.toInt(),
      linkedUrl: linked.optionalString('url'),
      review: review is Map
          ? MobilePullRequestReview.fromJson(Map<String, Object?>.from(review))
          : null,
    );
  }
}

abstract interface class MobileWorkspacePanelsClient {
  bool get supportsExplorer;
  bool get supportsWorkspaceSearch;
  bool get supportsSourceControl;
  bool get supportsPullRequests;

  Future<List<MobileExplorerEntry>> listExplorerChildren({
    required String workspaceId,
    String relativePath = '',
    bool hideIgnored = true,
  });

  Future<MobileWorkspaceSearchResult> searchWorkspace({
    required String workspaceId,
    required String query,
    bool caseSensitive = false,
    bool wholeWord = false,
    bool useRegex = false,
    String? includePattern,
    String? excludePattern,
    bool includeIgnored = false,
  });

  Future<MobileGitStatusSnapshot> gitStatus(String workspaceId);

  Future<MobileGitDiffFile> gitDiff({
    required String workspaceId,
    required String path,
    required String area,
  });

  Future<MobilePullRequestSnapshot> pullRequestSnapshot(String workspaceId);
}
