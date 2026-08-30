import 'package:alera/src/features/pull_requests/domain/review_comment_task_list.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'finds supported unordered, ordered, and quoted task items in order',
    () {
      const body = '''
- [ ] Same
  * [x] Nested
+ [X] Same
1) [ ] Ordered
> - [ ] Quoted
```text
- [ ] Code
```
''';

      final items = findReviewCommentTaskListItems(body);

      expect(items, hasLength(5));
      expect(items.map((item) => item.checked), <bool>[
        false,
        true,
        true,
        false,
        false,
      ]);
      expect(items.map((item) => body[item.markerOffset]), <String>[
        ' ',
        'x',
        'X',
        ' ',
        ' ',
      ]);
    },
  );

  test('toggles one duplicate without changing any other byte', () {
    const body = '- [ ] Same\r\n- [ ] Same\r\n';

    expect(
      toggleReviewCommentTaskListItem(body, 1),
      '- [ ] Same\r\n- [x] Same\r\n',
    );
    expect(toggleReviewCommentTaskListItem(body, 2), isNull);
  });

  test('unchecks uppercase markers with a one-character replacement', () {
    const body = '- [X] Keep formatting';

    expect(toggleReviewCommentTaskListItem(body, 0), '- [ ] Keep formatting');
  });

  test('copies a review comment without changing its body or locator', () {
    final original = ReviewComment(
      id: 'comment',
      author: 'alice',
      body: 'Body',
      createdAt: .utc(2026, 7, 16),
      kind: .review,
      locator: const ReviewCommentLocator(
        source: .reviewThread,
        commentId: '10',
        parentId: 'thread-1',
      ),
    );

    final copy = original.copyWith();

    expect(copy.body, 'Body');
    expect(copy.locator, same(original.locator));
  });
}
