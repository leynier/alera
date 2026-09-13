part of 'mobile_runtime_client.dart';

const Duration _workspaceSearchTimeout = Duration(minutes: 2);
const Duration _workspacePanelTimeout = Duration(seconds: 45);

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
  bool get supportsWorkspaceReplace =>
      runtimeCapabilities.contains(mobileWorkspaceReplaceCapability);

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
    String? replacement,
    bool preserveCase = false,
    String? requestId,
  }) async {
    _requireCapability(supportsWorkspaceSearch, 'search the workspace');
    // An older host would ignore these fields, so only send them when it can
    // answer with previews and honor the cancellation id.
    final withReplace = supportsWorkspaceReplace;
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
        if (withReplace && replacement != null && replacement.isNotEmpty) ...{
          'replacement': replacement,
          'preserveCase': preserveCase,
        },
        if (withReplace && requestId != null) 'requestId': requestId,
      }, _workspaceSearchTimeout),
    );
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
    _requireCapability(supportsWorkspaceReplace, 'replace workspace matches');
    return MobileWorkspaceReplaceResult.fromJson(
      await requestMap('mobile.workspaceSearch.replace', <String, Object?>{
        'workspaceId': workspaceId,
        'query': search.query,
        'caseSensitive': search.caseSensitive,
        'wholeWord': search.wholeWord,
        'useRegex': search.useRegex,
        'includeIgnored': search.includeIgnored,
        if (search.includePattern.trim().isNotEmpty)
          'includePattern': search.includePattern.trim(),
        if (search.excludePattern.trim().isNotEmpty)
          'excludePattern': search.excludePattern.trim(),
        'replacement': replacement,
        'preserveCase': preserveCase,
        'matchIds': matchIds,
        'expectedFiles': <Object?>[
          for (final file in expectedFiles)
            <String, Object?>{
              'relativePath': file.relativePath,
              'contentToken': file.contentToken,
            },
        ],
      }, _workspaceSearchTimeout),
    );
  }

  @override
  Future<void> cancelWorkspaceSearch(String requestId) async {
    if (!supportsWorkspaceReplace) {
      return;
    }
    await requestMap('mobile.workspaceSearch.cancel', <String, Object?>{
      'requestId': requestId,
    }, _workspacePanelTimeout);
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
