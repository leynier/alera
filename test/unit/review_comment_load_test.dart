import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment_load.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('optimistic comment edits preserve incomplete snapshot evidence', () {
    const state = WorkspacePullRequestState(commentsComplete: false);
    expect(state.copyWith(comments: []).commentsComplete, isFalse);
    const complete = WorkspacePullRequestState();
    expect(
      complete
          .copyWith(comments: ReviewCommentLoad([], complete: false))
          .commentsComplete,
      isFalse,
    );
    expect(complete.pollSignature, isNot(state.pollSignature));
  });
}
