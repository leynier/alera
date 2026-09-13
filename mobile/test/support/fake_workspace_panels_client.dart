import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';

mixin FakeWorkspacePanelsClient implements MobileWorkspacePanelsClient {
  List<String> get calls;

  bool explorerSupported = false;
  bool workspaceSearchSupported = false;
  bool sourceControlSupported = false;
  bool sourceControlWritesSupported = false;

  /// Answers a write; defaults to echoing [gitStatusSnapshot].
  MobileGitStatusSnapshot Function(MobileGitWrite write)? onGitWrite;
  final List<MobileGitWrite> gitWrites = <MobileGitWrite>[];

  /// Holds `gitWrite` open until completed, to observe a write in flight.
  Completer<void>? gitWriteGate;
  bool commitMessageGenerationSupported = false;
  MobileGitBranches gitBranchesResult = const MobileGitBranches();
  Future<GeneratedCommitMessage> Function(String operationId)?
  onGenerateCommitMessage;
  bool pullRequestsSupported = false;
  List<MobileExplorerEntry> explorerEntries = const <MobileExplorerEntry>[];
  MobileWorkspaceSearchResult searchResult =
      const MobileWorkspaceSearchResult();
  MobileGitStatusSnapshot gitStatusSnapshot = const MobileGitStatusSnapshot();

  /// Holds `gitStatus` open until completed, to observe a refresh in flight.
  Completer<void>? gitStatusGate;
  Object? gitStatusError;
  MobileGitDiffFile gitDiffFile = const MobileGitDiffFile(
    path: '',
    area: 'unstaged',
  );
  MobilePullRequestSnapshot pullRequest = const MobilePullRequestSnapshot();

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
    if (gitStatusError case final error?) {
      throw error;
    }
    return gitStatusSnapshot;
  }

  @override
  bool get supportsSourceControlWrites => sourceControlWritesSupported;

  @override
  bool get supportsCommitMessageGeneration => commitMessageGenerationSupported;

  @override
  Future<MobileGitBranches> gitBranches(String workspaceId) async {
    calls.add('gitBranches $workspaceId');
    return gitBranchesResult;
  }

  @override
  Future<GeneratedCommitMessage> generateCommitMessage({
    required String operationId,
    required String workspaceId,
  }) async {
    calls.add('generateCommitMessage $workspaceId');
    return onGenerateCommitMessage?.call(operationId) ??
        const GeneratedCommitMessage(message: 'Generated message');
  }

  @override
  Future<void> cancelCommitMessage(String operationId) async {
    calls.add('cancelCommitMessage $operationId');
  }

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
  }) async {
    calls.add('gitDiff $workspaceId $path $area');
    return gitDiffFile;
  }

  @override
  Future<MobilePullRequestSnapshot> pullRequestSnapshot(
    String workspaceId,
  ) async {
    calls.add('pullRequestSnapshot $workspaceId');
    return pullRequest;
  }
}
