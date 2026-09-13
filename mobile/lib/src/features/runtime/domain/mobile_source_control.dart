import 'package:alera_mobile/src/core/json_payload_fields.dart';

/// Upstream tracking and HEAD details of a workspace repository.
class const MobileGitRepositoryState({
  final String? upstream,
  final int ahead = 0,
  final int behind = 0,
  final bool hasConflicts = false,
  final String? headMessage,
  final bool detached = false,
}) {
  factory fromJson(Map<String, Object?> json) => MobileGitRepositoryState(
    upstream: json.optionalString('upstream'),
    ahead: (json['ahead'] as num?)?.toInt() ?? 0,
    behind: (json['behind'] as num?)?.toInt() ?? 0,
    hasConflicts: json['hasConflicts'] == true,
    headMessage: json.optionalString('headMessage'),
    detached: json['detached'] == true,
  );
}

class const MobileGitStash({
  required final int index,
  final String message = '',
}) {
  factory fromJson(Map<String, Object?> json) => MobileGitStash(
    index: (json['index'] as num?)?.toInt() ?? 0,
    message: json.optionalString('message') ?? '',
  );
}

/// Which source control actions the runtime allows right now. The runtime owns
/// these rules, so the phone renders them rather than re-deriving them; the
/// only local rule is that a commit needs a message.
class const MobileSourceControlActions({
  final bool commit = false,
  final bool commitPush = false,
  final bool commitSync = false,
  final bool amend = false,
  final bool stageAll = false,
  final bool unstageAll = false,
  final bool discardAll = false,
  final bool fetch = false,
  final bool pull = false,
  final bool push = false,
  final bool sync = false,
  final bool publishBranch = false,
  final bool stash = false,
  final bool stashPop = false,
}) {
  factory fromJson(Map<String, Object?> json) => MobileSourceControlActions(
    commit: json['commit'] == true,
    commitPush: json['commitPush'] == true,
    commitSync: json['commitSync'] == true,
    amend: json['amend'] == true,
    stageAll: json['stageAll'] == true,
    unstageAll: json['unstageAll'] == true,
    discardAll: json['discardAll'] == true,
    fetch: json['fetch'] == true,
    pull: json['pull'] == true,
    push: json['push'] == true,
    sync: json['sync'] == true,
    publishBranch: json['publishBranch'] == true,
    stash: json['stash'] == true,
    stashPop: json['stashPop'] == true,
  );
}

/// Branches a workspace can switch to. [branches] includes remote-tracking
/// names; switching to one creates the local tracking branch.
class const MobileGitBranches({
  final List<String> branches = const <String>[],
  final List<String> localBranches = const <String>[],
  final String? current,
}) {
  factory fromJson(Map<String, Object?> json) => MobileGitBranches(
    branches: <String>[
      for (final item in json.objectList('branches'))
        if (item is String) item,
    ],
    localBranches: <String>[
      for (final item in json.objectList('localBranches'))
        if (item is String) item,
    ],
    current: json.optionalString('current'),
  );
}

class const GeneratedCommitMessage({
  required final String message,
  final String? agentLabel,
});

enum MobileGitWriteAction {
  stage('mobile.git.stage'),
  unstage('mobile.git.unstage'),
  discard('mobile.git.discard'),
  commit('mobile.git.commit'),
  fetch('mobile.git.fetch'),
  pull('mobile.git.pull'),
  push('mobile.git.push'),
  sync('mobile.git.sync'),
  stash('mobile.git.stash'),
  stashPop('mobile.git.stashPop'),
  checkout('mobile.git.checkout'),
  createBranch('mobile.git.createBranch');

  MobileGitWriteAction(this.verb);

  final String verb;
}

/// What a commit does after it lands. Not atomic: a failed push keeps the
/// commit, exactly like desktop.
enum MobileCommitFollowUp { push, sync }

/// One source control write, as the runtime verb and payload it maps to.
class const MobileGitWrite._({
  required final MobileGitWriteAction action,
  final Map<String, Object?> arguments = const <String, Object?>{},
}) {
  /// Stages [path], every stageable entry of [area], or the whole tree.
  factory stage({String? path, String? area}) =>
      MobileGitWrite._(action: .stage, arguments: _selection(path, area));

  factory unstage({String? path, String? area}) =>
      MobileGitWrite._(action: .unstage, arguments: _selection(path, area));

  factory discard({String? path, String? area}) =>
      MobileGitWrite._(action: .discard, arguments: _selection(path, area));

  factory commit(
    String message, {
    bool amend = false,
    MobileCommitFollowUp? then,
  }) => MobileGitWrite._(
    action: .commit,
    arguments: <String, Object?>{
      'message': message,
      if (amend) 'amend': true,
      if (then != null) 'then': then.name,
    },
  );

  factory fetch() => const MobileGitWrite._(action: .fetch);

  factory pull() => const MobileGitWrite._(action: .pull);

  /// Pushes, publishing the branch to `origin` when it has no upstream.
  factory push() => const MobileGitWrite._(action: .push);

  factory sync() => const MobileGitWrite._(action: .sync);

  factory stash() => const MobileGitWrite._(action: .stash);

  factory stashPop(int stashIndex) => MobileGitWrite._(
    action: .stashPop,
    arguments: <String, Object?>{'stashIndex': stashIndex},
  );

  factory checkout(String branch) => MobileGitWrite._(
    action: .checkout,
    arguments: <String, Object?>{'branch': branch},
  );

  factory createBranch(String branch) => MobileGitWrite._(
    action: .createBranch,
    arguments: <String, Object?>{'branch': branch},
  );

  /// Whether the write talks to a remote, which can take far longer than a
  /// local index update.
  bool get usesNetwork => switch (action) {
    .fetch || .pull || .push || .sync => true,
    .commit => arguments.containsKey('then'),
    _ => false,
  };

  Map<String, Object?> payload(String workspaceId) => <String, Object?>{
    'workspaceId': workspaceId,
    ...arguments,
  };

  static Map<String, Object?> _selection(String? path, String? area) =>
      <String, Object?>{'path': ?path, 'area': ?area};
}
