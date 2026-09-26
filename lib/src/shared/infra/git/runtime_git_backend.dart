import 'dart:convert';
import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_explorer_status.dart';
import 'package:alera/src/shared/infra/git/git_remote.dart';
import 'package:alera/src/shared/infra/git/git_worktree_entry.dart';

part 'runtime_git_wire_decoders.dart';

/// The `errorCode` the runtime puts on a git failure; `errorDetails.kind`
/// carries the `GitErrorKind` name so the same [GitException] is thrown here
/// as `RustGitBackend` throws for a local checkout.
const String runtimeGitErrorCode = 'gitError';

const Duration _gitRequestTimeout = Duration(minutes: 2);
const Duration _gitNetworkTimeout = Duration(minutes: 5);

/// [GitBackend] for a workspace whose checkout lives on another host. Every
/// call becomes a `git.*` request the runtime forwards over that host's link;
/// the satellite runs the same `alera_core::source_control` code the bridge
/// runs locally. `path` is sent as-is (it is a path on the remote host) and
/// the satellite refuses anything outside the workspace.
///
/// Worktree lifecycle and clone are not part of this surface: remote
/// worktrees are created and removed through the managed workspace verbs.
class RuntimeGitBackend implements GitBackend {
  RuntimeGitBackend(
    this._client, {
    required this.workspaceId,
    this.beforeAccess,
  });

  final RuntimeHostClient _client;
  final String workspaceId;
  final Future<void> Function()? beforeAccess;

  @override
  Future<bool> isGitRepository(String path) async =>
      await _request('git.isRepository', path) == true;

  @override
  Future<List<String>> listBranches(String path) async =>
      _stringList(await _request('git.listBranches', path));

  @override
  Future<String> currentBranch(String path) async =>
      _string(await _request('git.currentBranch', path));

  @override
  Future<String> defaultBranch(String path) async =>
      _string(await _request('git.defaultBranch', path));

  @override
  Future<void> createAndCheckoutBranch({
    required String path,
    required String branch,
    String? expectedHead,
    String? expectedOid,
  }) => _request('git.createAndCheckoutBranch', path, {
    'branch': branch,
    'expectedHead': ?expectedHead,
    'expectedOid': ?expectedOid,
  });

  @override
  Future<void> resetBranchToRef({
    required String path,
    required String branch,
    required String targetRef,
    String? expectedOid,
  }) => _unsupported('resetBranchToRef');

  @override
  Future<void> checkoutBranch({required String path, required String branch}) =>
      _request('git.checkoutBranch', path, {'branch': branch});

  @override
  Future<bool> branchExists(String repoPath, String branch) async =>
      await _request('git.branchExists', repoPath, {'branch': branch}) == true;

  @override
  Future<bool> isAncestor({
    required String path,
    required String ancestorRef,
    required String descendantRef,
  }) async =>
      await _request('git.isAncestor', path, {
        'ancestorRef': ancestorRef,
        'descendantRef': descendantRef,
      }) ==
      true;

  @override
  Future<bool> isValidBranchName(String name) async =>
      await _request('git.isValidBranchName', null, {'name': name}) == true;

  @override
  Future<void> createWorktree({
    required String repoPath,
    required String targetBranch,
    required String path,
    required String sourceBranch,
    bool reuseExistingBranch = false,
  }) => _unsupported('createWorktree');

  @override
  Future<void> refreshSourceBranch({
    required String repoPath,
    required String sourceBranch,
  }) => _unsupported('refreshSourceBranch');

  @override
  Future<void> removeWorktree({
    required String repoPath,
    required String path,
    bool force = true,
  }) => _unsupported('removeWorktree');

  @override
  Future<void> deleteBranch({
    required String repoPath,
    required String branch,
    bool force = true,
  }) => _unsupported('deleteBranch');

  @override
  Future<List<GitWorktreeEntry>> listWorktrees(String repoPath) async => _list(
    await _request('git.listWorktrees', repoPath),
    (entry) => GitWorktreeEntry(
      path: _string(entry['path']),
      branch: _string(entry['branch']),
    ),
  );

  @override
  Future<List<GitRemote>> listRemotes(String path) async => _list(
    await _request('git.listRemotes', path),
    (remote) =>
        GitRemote(name: _string(remote['name']), url: remote['url'] as String?),
  );

  @override
  Future<void> clone({required String url, required String destinationPath}) =>
      _unsupported('clone');

  @override
  Future<GitStatusResult> status(String path) async =>
      _statusResult(_map(await _request('git.status', path)));

  @override
  Future<GitExplorerStatusSnapshot> explorerStatusSnapshot(String path) async =>
      _explorerSnapshot(_map(await _request('git.explorerStatus', path)));

  @override
  Future<GitStatusResult> statusForPath({
    required String path,
    required String filePath,
  }) async => _statusResult(
    _map(await _request('git.statusForPath', path, {'filePath': filePath})),
  );

  @override
  Future<GitStatusResult> submoduleStatus({
    required String path,
    required String submodulePath,
    required GitChangeArea area,
  }) async => _statusResult(
    _map(
      await _request('git.submoduleStatus', path, {
        'submodulePath': submodulePath,
        'area': _areaKey(area),
      }),
    ),
  );

  @override
  Future<GitDiffResult> diff({
    required String path,
    required String filePath,
    required GitChangeArea area,
  }) async => _diffResult(
    _map(
      await _request('git.diff', path, {
        'filePath': filePath,
        'area': _areaKey(area),
      }),
    ),
  );

  @override
  Future<GitDiffResult> diffAll({
    required String path,
    String? filePath,
  }) async => _diffResult(
    _map(await _request('git.diffAll', path, {'filePath': ?filePath})),
  );

  @override
  Future<Uint8List> readingDiffPatch({
    required String path,
    String? filePath,
    String? oldPath,
    GitChangeArea? area,
    String? commitOid,
    String? parentOid,
    String? baseRef,
  }) async {
    final payload = _map(
      await _request('git.readingDiffPatch', path, {
        'filePath': ?filePath,
        'oldPath': ?oldPath,
        if (area != null) 'area': _areaKey(area),
        'commitOid': ?commitOid,
        'parentOid': ?parentOid,
        'baseRef': ?baseRef,
      }),
    );
    return base64Decode(_string(payload['patchBase64']));
  }

  @override
  Future<Uint8List?> diffBlobBytes({
    required String path,
    required String filePath,
    String? oldPath,
    GitChangeArea? area,
    String? commitOid,
    String? parentOid,
    required bool oldSide,
  }) async {
    final payload = _map(
      await _request('git.diffBlobBytes', path, {
        'filePath': filePath,
        'oldPath': ?oldPath,
        if (area != null) 'area': _areaKey(area),
        'commitOid': ?commitOid,
        'parentOid': ?parentOid,
        'oldSide': oldSide,
      }),
    );
    final encoded = payload['bytesBase64'];
    return encoded is String ? base64Decode(encoded) : null;
  }

  @override
  Future<GitHistoryResult> history(
    String path, {
    int? limit,
    String? baseRef,
  }) async => _historyResult(
    _map(
      await _request('git.history', path, {
        'limit': ?limit,
        'baseRef': ?baseRef,
      }),
    ),
  );

  @override
  Future<GitCommitCompareResult> commitCompare({
    required String path,
    required String commitId,
  }) async => _commitCompareResult(
    _map(await _request('git.commitCompare', path, {'commitId': commitId})),
  );

  @override
  Future<GitDiffResult> commitDiff({
    required String path,
    required String commitOid,
    String? parentOid,
    String? filePath,
    String? oldPath,
  }) async => _diffResult(
    _map(
      await _request('git.commitDiff', path, {
        'commitOid': commitOid,
        'parentOid': ?parentOid,
        'filePath': ?filePath,
        'oldPath': ?oldPath,
      }),
    ),
  );

  @override
  Future<GitRangeContext> rangeContext(
    String path, {
    required String baseRef,
    int commitLimit = 40,
    String? headRef,
  }) async => _rangeContext(
    _map(
      await _request('git.rangeContext', path, {
        'baseRef': baseRef,
        'commitLimit': commitLimit,
        'headRef': ?headRef,
      }),
    ),
  );

  @override
  Future<GitRepositoryState> repositoryState(String path) async =>
      _repositoryState(_map(await _request('git.repositoryState', path)));

  @override
  Future<void> stage({required String path, String? filePath}) =>
      _request('git.stage', path, {'filePath': ?filePath});

  @override
  Future<void> stageArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  }) => _request('git.stageArea', path, {
    'area': _areaKey(area),
    'filePath': ?filePath,
  });

  @override
  Future<void> unstage({required String path, String? filePath}) =>
      _request('git.unstage', path, {'filePath': ?filePath});

  @override
  Future<void> unstageArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  }) => _request('git.unstageArea', path, {
    'area': _areaKey(area),
    'filePath': ?filePath,
  });

  @override
  Future<void> discard({required String path, String? filePath}) =>
      _request('git.discard', path, {'filePath': ?filePath});

  @override
  Future<void> discardArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  }) => _request('git.discardArea', path, {
    'area': _areaKey(area),
    'filePath': ?filePath,
  });

  @override
  Future<String> commit({
    required String path,
    required String message,
  }) async => _string(
    _map(await _request('git.commit', path, {'message': message}))['oid'],
  );

  @override
  Future<String> amendCommit({
    required String path,
    required String message,
  }) async => _string(
    _map(await _request('git.commitAmend', path, {'message': message}))['oid'],
  );

  @override
  Future<void> fetch(String path) =>
      _request('git.fetch', path, const {}, _gitNetworkTimeout);

  @override
  Future<GitHostedReviewRange> fetchHostedReviewRange({
    required String path,
    required String remote,
    required String baseBranch,
    required String headSha,
    String? headRemote,
    String? comparisonBaseSha,
    String? mergeCommitSha,
    String? reviewRef,
  }) async {
    final payload = _map(
      await _request('git.fetchHostedReviewRange', path, {
        'remote': remote,
        'baseBranch': baseBranch,
        'headSha': headSha,
        'headRemote': ?headRemote,
        'comparisonBaseSha': ?comparisonBaseSha,
        'mergeCommitSha': ?mergeCommitSha,
        'reviewRef': ?reviewRef,
      }, _gitNetworkTimeout),
    );
    return GitHostedReviewRange(
      baseOid: _string(payload['baseOid']),
      headOid: _string(payload['headOid']),
      retentionId: _string(payload['retentionId']),
    );
  }

  @override
  Future<void> persistHostedReviewRange({
    required String path,
    required String retentionId,
  }) => _request('git.persistHostedReviewRange', path, {
    'retentionId': retentionId,
  });

  @override
  Future<void> releaseHostedReviewRange({
    required String path,
    required String retentionId,
  }) => _request('git.releaseHostedReviewRange', path, {
    'retentionId': retentionId,
  });

  @override
  Future<void> pull(String path) =>
      _request('git.pull', path, const {}, _gitNetworkTimeout);

  @override
  Future<void> push(String path) =>
      _request('git.push', path, const {}, _gitNetworkTimeout);

  @override
  Future<List<GitStashEntry>> listStashes(String path) async =>
      _list(await _request('git.listStashes', path), _stashEntry);

  @override
  Future<void> stash(String path) => _request('git.stash', path);

  @override
  Future<void> stashPop({required String path, required int stashIndex}) =>
      _request('git.stashPop', path, {'stashIndex': stashIndex});

  Future<Object?> _request(
    String type,
    String? path, [
    Map<String, Object?> fields = const <String, Object?>{},
    Duration timeout = _gitRequestTimeout,
  ]) async {
    try {
      await beforeAccess?.call();
      return await _client.runtimeRequest(type, <String, Object?>{
        'workspaceId': workspaceId,
        'path': ?path,
        ...fields,
      }, timeout);
    } on TerminalHostConflictException catch (error) {
      if (error.code == runtimeGitErrorCode) {
        throw gitExceptionFromRuntime(error);
      }
      throw GitInternalException(error.message);
    } on GitException {
      rethrow;
    } catch (error) {
      throw GitInternalException(error.toString());
    }
  }

  Future<Never> _unsupported(String operation) => Future<Never>.error(
    GitInternalException(
      '$operation is not available for a workspace on a remote host.',
    ),
  );
}

/// Rebuilds the [GitException] the bridge would have thrown from the typed
/// `gitError` conflict the runtime answers with.
GitException gitExceptionFromRuntime(TerminalHostConflictException error) {
  final context = switch (error.details['context']) {
    final String context => context,
    _ => error.message,
  };
  return switch (error.details['kind']) {
    'notARepository' => NotARepositoryException(context),
    'accessDenied' => AccessDeniedException(context),
    'branchNotFound' => BranchNotFoundException(context),
    'branchAlreadyExists' => BranchAlreadyExistsException(context),
    'invalidBranchName' => InvalidBranchNameException(context),
    'worktreeAlreadyExists' => WorktreeAlreadyExistsException(context),
    'worktreeNotFound' => WorktreeNotFoundException(context),
    'cloneFailed' => CloneFailedException(context),
    'gitCli' => GitCliException(context),
    'detachedHead' => DetachedHeadException(context),
    'noUpstream' => NoUpstreamException(context),
    'remoteNotFound' => RemoteNotFoundException(context),
    'nothingToCommit' => NothingToCommitException(context),
    'workspaceScope' => WorkspaceScopeException(context),
    'missingIdentity' => MissingIdentityException(context),
    'conflict' => GitConflictException(context),
    _ => GitInternalException(context),
  };
}
