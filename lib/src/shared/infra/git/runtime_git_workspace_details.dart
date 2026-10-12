part of 'runtime_git_backend.dart';

mixin _RuntimeGitWorkspaceDetails implements GitBackend {
  RuntimeHostClient get _client;
  Future<void> Function()? get beforeAccess;
  Future<Object?> _request(
    String type,
    String? path, [
    Map<String, Object?> fields = const {},
    Duration timeout = _gitRequestTimeout,
  ]);
  @override
  Future<String> workspaceDefaultBranch(String path) async {
    await _requireWorkspaceDetails();
    return _string(await _request('git.workspaceDefaultBranch', path));
  }

  @override
  Future<GitWorkspaceComparison> workspaceComparison(
    String path, {
    String? baseRef,
  }) async {
    await _requireWorkspaceDetails();
    return GitWorkspaceComparison.fromJson(
      _map(
        await _request('git.workspaceComparison', path, {
          'baseRef': ?baseRef,
        }, _gitRequestTimeout),
      ),
    );
  }

  @override
  Future<GitDiffResult> workspaceComparisonDiff(
    String path,
    GitWorkspaceComparison snapshot,
    String filePath,
  ) async {
    await _requireWorkspaceDetails();
    return _diffResult(
      _map(
        await _request('git.workspaceComparisonDiff', path, {
          'snapshot': snapshot.toJson(),
          'filePath': filePath,
        }),
      ),
    );
  }

  @override
  Future<String> commitSelected(
    String path,
    GitWorkspaceComparison snapshot,
    List<String> filePaths,
    String message,
  ) async {
    await _requireWorkspaceDetails();
    return _string(
      await _request('git.commitSelected', path, {
        'snapshot': snapshot.toJson(),
        'filePaths': filePaths,
        'message': message,
      }),
    );
  }

  Future<void> _requireWorkspaceDetails() async {
    await beforeAccess?.call();
    if (_client case final RuntimeHostCapabilityClient capabilities) {
      if (!await capabilities.supportsRuntimeCapability('workspaceDetailsV1')) {
        throw const GitInternalException(
          'Update the runtime to use workspace details.',
        );
      }
    }
  }
}
