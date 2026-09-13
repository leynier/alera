import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';

mixin FakeWorkspacePanelsClient implements MobileWorkspacePanelsClient {
  List<String> get calls;

  bool explorerSupported = false;
  bool workspaceSearchSupported = false;
  bool sourceControlSupported = false;
  bool pullRequestsSupported = false;
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
  }) async {
    calls.add('searchWorkspace $workspaceId $query');
    return searchResult;
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
