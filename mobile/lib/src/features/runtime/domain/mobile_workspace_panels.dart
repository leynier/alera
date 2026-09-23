import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_source_control.dart';

export 'package:alera_mobile/src/core/mobile_protocol.dart'
    show
        aiTextCommitMessageCapability,
        mobileExplorerCapability,
        mobilePullRequestCapability,
        mobileSourceControlCapability,
        mobileWorkspaceReplaceCapability,
        mobileSourceControlRootCapability,
        mobileSourceControlWritesCapability,
        mobileWorkspaceSearchCapability;
export 'package:alera_mobile/src/features/runtime/domain/mobile_source_control.dart';

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
  final int? displayColumn,
  final int? displayMatchLength,
  final String? replacementPreview,
}) {
  factory fromJson(Map<String, Object?> json) => MobileWorkspaceSearchMatch(
    id: json.requiredString('id'),
    line: (json['line'] as num?)?.toInt() ?? 1,
    column: (json['column'] as num?)?.toInt() ?? 1,
    matchLength: (json['matchLength'] as num?)?.toInt() ?? 0,
    lineContent: json.optionalString('lineContent') ?? '',
    displayColumn: (json['displayColumn'] as num?)?.toInt(),
    displayMatchLength: (json['displayMatchLength'] as num?)?.toInt(),
    replacementPreview: json['replacementPreview'] as String?,
  );
}

class const MobileWorkspaceSearchFile({
  required final String relativePath,
  final String contentToken = '',
  final List<MobileWorkspaceSearchMatch> matches =
      const <MobileWorkspaceSearchMatch>[],
}) {
  factory fromJson(Map<String, Object?> json) => MobileWorkspaceSearchFile(
    relativePath: json.requiredString('relativePath'),
    contentToken: json.optionalString('contentToken') ?? '',
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

class const MobileWorkspaceReplaceConflict({
  required final String relativePath,
  required final String reason,
}) {
  factory fromJson(Map<String, Object?> json) => MobileWorkspaceReplaceConflict(
    relativePath: json.optionalString('relativePath') ?? 'unknown',
    reason: json.optionalString('reason') ?? '',
  );
}

class const MobileWorkspaceReplaceResult({
  final int filesChanged = 0,
  final int matchesReplaced = 0,
  final List<MobileWorkspaceReplaceConflict> conflicts =
      const <MobileWorkspaceReplaceConflict>[],
}) {
  factory fromJson(Map<String, Object?> json) => MobileWorkspaceReplaceResult(
    filesChanged: (json['filesChanged'] as num?)?.toInt() ?? 0,
    matchesReplaced: (json['matchesReplaced'] as num?)?.toInt() ?? 0,
    conflicts: <MobileWorkspaceReplaceConflict>[
      for (final item in json.objectList('conflicts'))
        if (item is Map)
          MobileWorkspaceReplaceConflict.fromJson(
            Map<String, Object?>.from(item),
          ),
    ],
  );
}

/// The search a replace re-runs on the host. It must match the search that
/// produced the results, because the host re-derives the match ids from it.
class const MobileWorkspaceSearchQuery({
  required final String query,
  final bool caseSensitive = false,
  final bool wholeWord = false,
  final bool useRegex = false,
  final String includePattern = '',
  final String excludePattern = '',
  final bool includeIgnored = false,
});

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

/// A pull request comment. [kind] is `review` for a comment on a diff thread
/// ([threadId], [path], [line], [resolved]); [source] is `reviewSummary` for
/// the body of a submitted review. Hosts older than these fields send only
/// conversation comments, which the defaults describe.
class const MobilePullRequestComment({
  required final int id,
  final String? author,
  final String body = '',
  final String? createdAt,
  final String? url,
  final String kind = 'conversation',
  final String source = 'conversation',
  final String? path,
  final int? line,
  final bool resolved = false,
  final bool outdated = false,
  final String? threadId,
  final bool canEdit = false,
}) {
  bool get isReviewThread => kind == 'review';

  bool get isReviewSummary => source == 'reviewSummary';

  DateTime? get createdAtTime {
    final value = createdAt;
    return value == null ? null : DateTime.tryParse(value);
  }

  factory fromJson(Map<String, Object?> json) => MobilePullRequestComment(
    id: (json['id'] as num?)?.toInt() ?? 0,
    author: json.optionalString('author'),
    body: json.optionalString('body') ?? '',
    createdAt: json.optionalString('createdAt'),
    url: json.optionalString('url'),
    kind: json.optionalString('kind') ?? 'conversation',
    source: json.optionalString('source') ?? 'conversation',
    path: json.optionalString('path'),
    line: (json['line'] as num?)?.toInt(),
    resolved: json['resolved'] == true,
    outdated: json['outdated'] == true,
    threadId: json.optionalString('threadId'),
    canEdit: json['canEdit'] == true,
  );
}

/// A review the user unlinked from the workspace, offered to link again.
class const MobilePullRequestSuggestedReview({
  required final int number,
  final String? title,
  final String? url,
});

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
  final String? headSha,
  final List<MobilePullRequestCheck> checks = const <MobilePullRequestCheck>[],
  final bool commentsTruncated = false,
  final List<MobilePullRequestComment> comments =
      const <MobilePullRequestComment>[],
}) {
  bool get isOpen => state.toUpperCase() == 'OPEN';

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
    headSha: json.optionalString('headSha'),
    checks: <MobilePullRequestCheck>[
      for (final item in json.objectList('checks'))
        if (item is Map)
          MobilePullRequestCheck.fromJson(Map<String, Object?>.from(item)),
    ],
    commentsTruncated: json['commentsTruncated'] == true,
    comments: <MobilePullRequestComment>[
      for (final item in json.objectList('comments'))
        if (item is Map)
          MobilePullRequestComment.fromJson(Map<String, Object?>.from(item)),
    ],
  );
}

class const MobilePullRequestIdentity({
  final String? provider,
  final String? host,
  final String? owner,
  final String? repo,
}) {
  String? get label {
    if (owner != null && repo != null) {
      return '$owner/$repo';
    }
    return host ?? provider;
  }

  factory fromJson(Map<String, Object?> json) => MobilePullRequestIdentity(
    provider: json.optionalString('provider'),
    host: json.optionalString('host'),
    owner: json.optionalString('owner'),
    repo: json.optionalString('repo'),
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
  final MobilePullRequestIdentity? identity,
  final MobilePullRequestReview? review,
  final String? viewerLogin,
  final bool canComment = false,
  final List<String> mergeMethods = const <String>[],
  final String? mergeMethodsError,
  final List<String> baseBranches = const <String>[],
  final String? suggestedBaseBranch,
  final bool aiAssistEnabled = false,
  final MobilePullRequestSuggestedReview? suggestedReview,
}) {
  factory fromJson(Map<String, Object?> json) {
    final linked = json.mapValue('linkedReview');
    final identity = json.mapValue('identity');
    final review = json['review'];
    final suggested = json.mapValue('suggestedReview');
    final suggestedNumber = (suggested['number'] as num?)?.toInt();
    return MobilePullRequestSnapshot(
      viewerLogin: json.optionalString('viewerLogin'),
      canComment: json['canComment'] == true,
      mergeMethods: <String>[
        for (final item in json.objectList('mergeMethods'))
          if (item is String) item,
      ],
      mergeMethodsError: json.optionalString('mergeMethodsError'),
      baseBranches: <String>[
        for (final item in json.objectList('baseBranches'))
          if (item is String) item,
      ],
      suggestedBaseBranch: json.optionalString('suggestedBaseBranch'),
      aiAssistEnabled: json['aiAssistEnabled'] == true,
      suggestedReview: suggestedNumber == null
          ? null
          : MobilePullRequestSuggestedReview(
              number: suggestedNumber,
              title: suggested.optionalString('title'),
              url: suggested.optionalString('url'),
            ),
      branch: json.optionalString('branch'),
      remoteUrl: json.optionalString('remoteUrl'),
      provider: json.optionalString('provider'),
      authStatus: json.optionalString('authStatus'),
      unavailableReason: json.optionalString('unavailableReason'),
      linkedNumber: (linked['number'] as num?)?.toInt(),
      linkedUrl: linked.optionalString('url'),
      identity: identity.isEmpty
          ? null
          : MobilePullRequestIdentity.fromJson(identity),
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
  bool get supportsWorkspaceReplace;

  /// Whether `gitStatus` and `gitDiff` honor [relativeRoot]. A host without
  /// it would silently answer for the workspace root instead.
  bool get supportsSourceControlRoot;

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
    String? replacement,
    bool preserveCase = false,
    String? requestId,
  });

  Future<MobileWorkspaceReplaceResult> replaceWorkspaceMatches({
    required String workspaceId,
    required MobileWorkspaceSearchQuery search,
    required String replacement,
    bool preserveCase = false,
    required List<String> matchIds,
    required List<MobileWorkspaceSearchFile> expectedFiles,
  });

  Future<void> cancelWorkspaceSearch(String requestId);

  Future<MobileGitStatusSnapshot> gitStatus(
    String workspaceId, {
    String relativeRoot = '',
  });

  bool get supportsSourceControlWrites;

  bool get supportsCommitMessageGeneration;

  Future<MobileGitBranches> gitBranches(String workspaceId);

  /// Asks the runtime's AI Assist agent for a message over the staged changes.
  Future<GeneratedCommitMessage> generateCommitMessage({
    required String operationId,
    required String workspaceId,
  });

  Future<void> cancelCommitMessage(String operationId);

  /// Runs [write] and resolves with the status snapshot that follows it.
  Future<MobileGitStatusSnapshot> gitWrite(
    String workspaceId,
    MobileGitWrite write,
  );

  Future<MobileGitDiffFile> gitDiff({
    required String workspaceId,
    required String path,
    required String area,
    String relativeRoot = '',
  });

  Future<MobilePullRequestSnapshot> pullRequestSnapshot(String workspaceId);
}
