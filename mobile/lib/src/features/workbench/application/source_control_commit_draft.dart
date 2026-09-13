import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'source_control_commit_draft.g.dart';

/// The commit message being typed for a workspace. Kept alive so switching
/// panels or opening a diff does not throw the message away.
@Riverpod(keepAlive: true)
class SourceControlCommitDraft extends _$SourceControlCommitDraft {
  @override
  String build(String hostId, String workspaceId) => '';

  void update(String message) {
    state = message;
  }

  void clear() {
    state = '';
  }
}
