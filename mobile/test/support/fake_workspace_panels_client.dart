import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';

mixin FakeWorkspacePanelsClient implements MobileWorkspacePanelsClient {
  List<String> get calls;

  bool explorerSupported = false;
  bool workspaceSearchSupported = false;
  bool sourceControlSupported = false;
  bool pullRequestsSupported = false;
  bool workspaceReplaceSupported = false;
  MobileWorkspaceReplaceResult replaceResult =
      const MobileWorkspaceReplaceResult();
  final List<Map<String, Object?>> searchRequests = <Map<String, Object?>>[];
  final List<Map<String, Object?>> replaceRequests = <Map<String, Object?>>[];
  List<MobileExplorerEntry> explorerEntries = const <MobileExplorerEntry>[];
  MobileWorkspaceSearchResult searchResult =
      const MobileWorkspaceSearchResult();
  MobileGitStatusSnapshot gitStatusSnapshot = const MobileGitStatusSnapshot();
  MobileGitDiffFile gitDiffFile = const MobileGitDiffFile(
    path: '',
    area: 'unstaged',
  );
  MobilePullRequestSnapshot pullRequest = const MobilePullRequestSnapshot();

  /// Holds the next responses open until completed, to observe a refresh in
  /// flight. Errors make the call fail after the gate opens.
  Completer<void>? explorerGate;
  Object? explorerError;
  Completer<void>? gitStatusGate;
  Object? gitStatusError;
  Completer<void>? pullRequestGate;
  Object? pullRequestError;

  @override
  bool get supportsExplorer => explorerSupported;

  @override
  bool get supportsWorkspaceSearch => workspaceSearchSupported;

  @override
  bool get supportsSourceControl => sourceControlSupported;

  @override
  bool get supportsPullRequests => pullRequestsSupported;

  @override
  bool get supportsWorkspaceReplace => workspaceReplaceSupported;

  @override
  Future<List<MobileExplorerEntry>> listExplorerChildren({
    required String workspaceId,
    String relativePath = '',
    bool hideIgnored = true,
  }) async {
    calls.add('listExplorerChildren $workspaceId $relativePath');
    await explorerGate?.future;
    if (explorerError case final error?) throw error;
    return explorerEntries
        .where(
          (entry) => relativePath.isEmpty
              ? !entry.relativePath.contains('/')
              : entry.relativePath.startsWith('$relativePath/') &&
                    !entry.relativePath
                        .substring(relativePath.length + 1)
                        .contains('/'),
        )
        .toList(growable: false);
  }

  @override
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
  }) async {
    calls.add('searchWorkspace $workspaceId $query');
    searchRequests.add(<String, Object?>{
      'query': query,
      'includeIgnored': includeIgnored,
      'replacement': replacement,
      'preserveCase': preserveCase,
      'requestId': requestId,
    });
    return searchResult;
  }

  @override
  Future<MobileWorkspaceReplaceResult> replaceWorkspaceMatches({
    required String workspaceId,
    required MobileWorkspaceSearchQuery search,
    required String replacement,
    bool preserveCase = false,
    required List<String> matchIds,
    required List<MobileWorkspaceSearchFile> expectedFiles,
  }) async {
    calls.add('replaceWorkspaceMatches $workspaceId ${search.query}');
    replaceRequests.add(<String, Object?>{
      'replacement': replacement,
      'preserveCase': preserveCase,
      'matchIds': matchIds,
      'expectedFiles': <String, String>{
        for (final file in expectedFiles) file.relativePath: file.contentToken,
      },
    });
    return replaceResult;
  }

  @override
  Future<void> cancelWorkspaceSearch(String requestId) async {
    calls.add('cancelWorkspaceSearch $requestId');
  }

  @override
  Future<MobileGitStatusSnapshot> gitStatus(String workspaceId) async {
    calls.add('gitStatus $workspaceId');
    await gitStatusGate?.future;
    if (gitStatusError case final error?) throw error;
    return gitStatusSnapshot;
  }

  @override
  Future<MobileGitDiffFile> gitDiff({
    required String workspaceId,
    required String path,
    required String area,
  }) async {
    calls.add('gitDiff $workspaceId $path $area');
    return gitDiffFile;
  }

  @override
  Future<MobilePullRequestSnapshot> pullRequestSnapshot(
    String workspaceId,
  ) async {
    calls.add('pullRequestSnapshot $workspaceId');
    await pullRequestGate?.future;
    if (pullRequestError case final error?) throw error;
    return pullRequest;
  }
}
