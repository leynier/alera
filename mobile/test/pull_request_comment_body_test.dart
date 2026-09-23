import 'package:alera_mobile/src/features/workbench/domain/pull_request_comment_body.dart';
import 'package:flutter_test/flutter_test.dart';

// Guards the mobile copy of the comment sanitizer against drift from the
// desktop original
// (lib/src/features/pull_requests/domain/pull_request_comment_body.dart).
// Full behavior is covered there; this file pins the cases that matter for
// the phone conversation view.
void main() {
  test('converts bot html footers to markdown images and links', () {
    const body =
        'New pull request. Leaping into action...\n\n'
        '<!-- PULLFROG_DIVIDER_DO_NOT_REMOVE_PLZ -->\n'
        '<sub><a href="https://pullfrog.com"><picture>'
        '<source media="(prefers-color-scheme: dark)" '
        'srcset="https://pullfrog.com/logos/frog-white-full-18px.png">'
        '<img src="https://pullfrog.com/logos/frog-green-full-18px.png" '
        'width="9px" height="9px" alt="Pullfrog"></picture></a>&nbsp;&nbsp; | '
        '[View workflow run](https://example.com/run) | via '
        '[Pullfrog](https://pullfrog.com)</sub>';
    final sanitized = sanitizePullRequestCommentBody(body);

    expect(sanitized, isNot(contains('<picture')));
    expect(sanitized, isNot(contains('<img')));
    expect(sanitized, isNot(contains('<!--')));
    expect(
      sanitized,
      contains(
        '![9x9 Pullfrog](https://pullfrog.com/logos/frog-white-full-18px.png)',
      ),
    );
    expect(sanitized, contains('[View workflow run](https://example.com/run)'));
  });

  test('encodes html image pixel sizes in the markdown alt', () {
    expect(
      sanitizePullRequestCommentBody(
        '<img src="https://uploads.pullfrog.com/Progress%20Indicator.gif" '
        'width="11">',
      ),
      '![11](https://uploads.pullfrog.com/Progress%20Indicator.gif)',
    );
  });

  test('leaves fenced code untouched', () {
    const body = '```html\n<img src="x">\n```';
    expect(sanitizePullRequestCommentBody(body), body);
  });

  test('converts blockquotes to markdown quote lines', () {
    expect(
      sanitizePullRequestCommentBody('<blockquote>quoted</blockquote>'),
      '\n\n> quoted\n\n',
    );
  });
}
