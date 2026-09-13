part of 'mobile_runtime_client.dart';

const Duration _workspaceSearchTimeout = Duration(minutes: 2);
const Duration _workspacePanelTimeout = Duration(seconds: 45);
const Duration _gitNetworkTimeout = Duration(minutes: 5);

/// The runtime caps an agent run at 600 seconds; this leaves room for the
/// staged diff to be read before the agent starts.
const Duration _commitMessageTimeout = Duration(minutes: 11);

mixin MobileRuntimeWorkspacePanelRequests
    implements MobileWorkspacePanelsClient {
  Set<String> get runtimeCapabilities;

  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  @override
  bool get supportsExplorer =>
      runtimeCapabilities.contains(mobileExplorerCapability);

  @override
  bool get supportsWorkspaceSearch =>
      runtimeCapabilities.contains(mobileWorkspaceSearchCapability);

  @override
  bool get supportsSourceControl =>
      runtimeCapabilities.contains(mobileSourceControlCapability);

  @override
  bool get supportsPullRequests =>
      runtimeCapabilities.contains(mobilePullRequestCapability);

  @override
  Future<List<MobileExplorerEntry>> listExplorerChildren({
    required String workspaceId,
    String relativePath = '',
    bool hideIgnored = true,
  }) async {
    _requireCapability(supportsExplorer, 'browse the workspace explorer');
    final payload = await requestMap(
      'mobile.workspaceExplorer.list',
      <String, Object?>{
        'workspaceId': workspaceId,
        'relativePath': relativePath,
        'hideIgnored': hideIgnored,
      },
      _workspacePanelTimeout,
    );
    return <MobileExplorerEntry>[
      for (final item in payload.objectList('entries'))
        if (item is Map)
          MobileExplorerEntry.fromJson(Map<String, Object?>.from(item)),
    ];
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
    _requireCapability(supportsWorkspaceSearch, 'search the workspace');
    return MobileWorkspaceSearchResult.fromJson(
      await requestMap('mobile.workspaceSearch.run', <String, Object?>{
        'workspaceId': workspaceId,
        'query': query,
        'caseSensitive': caseSensitive,
        'wholeWord': wholeWord,
        'useRegex': useRegex,
        'includeIgnored': includeIgnored,
        if (includePattern != null && includePattern.trim().isNotEmpty)
          'includePattern': includePattern.trim(),
        if (excludePattern != null && excludePattern.trim().isNotEmpty)
          'excludePattern': excludePattern.trim(),
      }, _workspaceSearchTimeout),
    );
  }

  @override
  Future<MobileGitStatusSnapshot> gitStatus(String workspaceId) async {
    _requireCapability(supportsSourceControl, 'read source control');
    return MobileGitStatusSnapshot.fromJson(
      await requestMap('mobile.git.status', <String, Object?>{
        'workspaceId': workspaceId,
      }, _workspacePanelTimeout),
    );
  }

  @override
  bool get supportsSourceControlWrites =>
      runtimeCapabilities.contains(mobileSourceControlWritesCapability);

  @override
  bool get supportsCommitMessageGeneration =>
      runtimeCapabilities.contains(aiTextCommitMessageCapability);

  @override
  Future<MobileGitBranches> gitBranches(String workspaceId) async {
    _requireCapability(supportsSourceControlWrites, 'switch branches');
    return MobileGitBranches.fromJson(
      await requestMap('mobile.git.branches', <String, Object?>{
        'workspaceId': workspaceId,
      }, _workspacePanelTimeout),
    );
  }

  @override
  Future<GeneratedCommitMessage> generateCommitMessage({
    required String operationId,
    required String workspaceId,
  }) async {
    _requireCapability(
      supportsCommitMessageGeneration,
      'generate commit messages',
    );
    final payload = await requestMap(
      'aiText.commitMessage.generate',
      <String, Object?>{'operationId': operationId, 'workspaceId': workspaceId},
      _commitMessageTimeout,
    );
    return GeneratedCommitMessage(
      message: payload.requiredString('message'),
      agentLabel: payload.optionalString('agentLabel'),
    );
  }

  @override
  Future<void> cancelCommitMessage(String operationId) async {
    await requestMap('aiText.cancel', <String, Object?>{
      'operationId': operationId,
    });
  }

  @override
  Future<MobileGitStatusSnapshot> gitWrite(
    String workspaceId,
    MobileGitWrite write,
  ) async {
    _requireCapability(
      supportsSourceControlWrites,
      'change source control from mobile',
    );
    return MobileGitStatusSnapshot.fromJson(
      await requestMap(
        write.action.verb,
        write.payload(workspaceId),
        write.usesNetwork ? _gitNetworkTimeout : _workspacePanelTimeout,
      ),
    );
  }

  @override
  Future<MobileGitDiffFile> gitDiff({
    required String workspaceId,
    required String path,
    required String area,
  }) async {
    _requireCapability(supportsSourceControl, 'read source control diffs');
    return MobileGitDiffFile.fromJson(
      await requestMap('mobile.git.diff', <String, Object?>{
        'workspaceId': workspaceId,
        'path': path,
        'area': area,
      }, _workspacePanelTimeout),
    );
  }

  @override
  Future<MobilePullRequestSnapshot> pullRequestSnapshot(
    String workspaceId,
  ) async {
    _requireCapability(supportsPullRequests, 'load pull requests');
    return MobilePullRequestSnapshot.fromJson(
      await requestMap('mobile.pullRequest.snapshot', <String, Object?>{
        'workspaceId': workspaceId,
      }, _workspacePanelTimeout),
    );
  }

  void _requireCapability(bool supported, String action) {
    if (!supported) {
      throw UnsupportedError('Update the paired Alera runtime to $action.');
    }
  }
}
