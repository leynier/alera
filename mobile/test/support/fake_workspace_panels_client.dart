import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';

mixin FakeWorkspacePanelsClient implements MobileWorkspacePanelsClient {
  List<String> get calls;

  Completer<void>? explorerGate;
  Object? explorerError;
  Completer<void>? gitStatusGate;
  Object? gitStatusError;
  Completer<void>? pullRequestGate;
  Object? pullRequestError;

  bool explorerSupported = false;
  bool workspaceSearchSupported = false;
  bool sourceControlSupported = false;
  bool sourceControlWritesSupported = false;

  /// Answers a write; defaults to echoing [gitStatusSnapshot].
  MobileGitStatusSnapshot Function(MobileGitWrite write)? onGitWrite;
  final List<MobileGitWrite> gitWrites = <MobileGitWrite>[];

  /// Holds `gitWrite` open until completed, to observe a write in flight.
  Completer<void>? gitWriteGate;
  bool pullRequestsSupported = false;
  bool workspaceReplaceSupported = false;
  MobileWorkspaceReplaceResult replaceResult =
      const MobileWorkspaceReplaceResult();
  final List<Map<String, Object?>> searchRequests = <Map<String, Object?>>[];
  final List<Map<String, Object?>> replaceRequests = <Map<String, Object?>>[];
  bool sourceControlRootSupported = false;
  Set<String> gitRepositoryRoots = const <String>{''};
  List<MobileExplorerEntry> ignoredExplorerEntries =
      const <MobileExplorerEntry>[];
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
  Completer<void>? replaceGate;
  Completer<void>? searchGate;

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
  bool get supportsSourceControlRoot => sourceControlRootSupported;

  @override
  Future<List<MobileExplorerEntry>> listExplorerChildren({
    required String workspaceId,
    String relativePath = '',
    bool hideIgnored = true,
  }) async {
    calls.add(
      'listExplorerChildren $workspaceId $relativePath'
      '${hideIgnored ? '' : ' showAll'}',
    );
    await explorerGate?.future;
    if (explorerError case final error?) throw error;
    return <MobileExplorerEntry>[
          ...explorerEntries,
          if (!hideIgnored) ...ignoredExplorerEntries,
        ]
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
    await searchGate?.future;
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
    await replaceGate?.future;
    return replaceResult;
  }

  @override
  Future<void> cancelWorkspaceSearch(String requestId) async {
    calls.add('cancelWorkspaceSearch $requestId');
  }

  @override
  Future<MobileGitStatusSnapshot> gitStatus(
    String workspaceId, {
    String relativeRoot = '',
  }) async {
    calls.add(
      'gitStatus $workspaceId${relativeRoot.isEmpty ? '' : ' $relativeRoot'}',
    );
    await gitStatusGate?.future;
    if (gitStatusError case final error?) throw error;
    if (!gitRepositoryRoots.contains(relativeRoot)) {
      return const MobileGitStatusSnapshot();
    }
    return gitStatusSnapshot;
  }

  @override
  bool get supportsSourceControlWrites => sourceControlWritesSupported;

  @override
  Future<MobileGitStatusSnapshot> gitWrite(
    String workspaceId,
    MobileGitWrite write,
  ) async {
    calls.add('gitWrite $workspaceId ${write.action.verb}');
    gitWrites.add(write);
    await gitWriteGate?.future;
    return onGitWrite?.call(write) ?? gitStatusSnapshot;
  }

  @override
  Future<MobileGitDiffFile> gitDiff({
    required String workspaceId,
    required String path,
    required String area,
    String relativeRoot = '',
  }) async {
    calls.add(
      'gitDiff $workspaceId $path $area'
      '${relativeRoot.isEmpty ? '' : ' $relativeRoot'}',
    );
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
