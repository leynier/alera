import 'package:alera/src/features/pull_requests/domain/pull_request_comment_body.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('leaves plain markdown untouched', () {
    const body = '**Important**\n\n- First item\n';
    expect(sanitizePullRequestCommentBody(body), body);
  });

  test('strips html comments', () {
    expect(
      sanitizePullRequestCommentBody('Before\n<!-- hidden -->\nAfter'),
      'Before\n\nAfter',
    );
  });

  test('converts img tags to markdown images', () {
    expect(
      sanitizePullRequestCommentBody(
        '<img src="https://example.com/logo.png" alt="Logo">',
      ),
      '![Logo](https://example.com/logo.png)',
    );
  });

  test('prefers the dark picture source on this dark-only app', () {
    const body =
        '<picture><source media="(prefers-color-scheme: dark)" '
        'srcset="https://example.com/dark.png">'
        '<img src="https://example.com/light.png" alt="Logo"></picture>';
    expect(
      sanitizePullRequestCommentBody(body),
      '![Logo](https://example.com/dark.png)',
    );
  });

  test('converts anchors to markdown links and drops unsafe schemes', () {
    expect(
      sanitizePullRequestCommentBody(
        '<a href="https://example.com/run">View run</a>',
      ),
      '[View run](https://example.com/run)',
    );
    expect(
      sanitizePullRequestCommentBody('<a href="javascript:alert(1)">Click</a>'),
      'Click',
    );
  });

  test('keeps linked images as images so they still paint', () {
    expect(
      sanitizePullRequestCommentBody(
        '<a href="https://example.com">'
        '<img src="https://example.com/logo.png" alt="Logo">'
        '</a>',
      ),
      '![Logo](https://example.com/logo.png)',
    );
  });

  test('converts inline formatting and breaks', () {
    expect(
      sanitizePullRequestCommentBody('<b>bold</b> and <i>italic</i>'),
      '**bold** and *italic*',
    );
    expect(sanitizePullRequestCommentBody('one<br>two'), 'one  \ntwo');
  });

  test('decodes entities without eating escaped tags', () {
    expect(
      sanitizePullRequestCommentBody('a &amp; b&nbsp;&nbsp;| c'),
      'a & b  | c',
    );
    expect(sanitizePullRequestCommentBody('a &lt;b&gt; c'), 'a <b> c');
  });

  test('leaves fenced code and inline code untouched', () {
    const body = '```html\n<img src="x">\n```\n\n`<a href="x">y</a>`';
    expect(sanitizePullRequestCommentBody(body), body);
  });

  test('renders the pullfrog bot footer without raw tags', () {
    const body =
        'New pull request. Leaping into action...\n\n'
        '<!-- PULLFROG_DIVIDER_DO_NOT_REMOVE_PLZ -->\n'
        '<sub><a href="https://pullfrog.com"><picture>'
        '<source media="(prefers-color-scheme: dark)" '
        'srcset="https://pullfrog.com/logos/frog-white-full-18px.png">'
        '<img src="https://pullfrog.com/logos/frog-green-full-18px.png" '
        'width="9px" height="9px" style="vertical-align: middle;" '
        'alt="Pullfrog"></picture></a>&nbsp;&nbsp; | '
        '[View workflow run](https://example.com/run) | via '
        '[Pullfrog](https://pullfrog.com) | Using '
        '[6rok](https://6rok.com) | [X](https://x.com)</sub>';
    final sanitized = sanitizePullRequestCommentBody(body);

    expect(sanitized, isNot(contains('<picture')));
    expect(sanitized, isNot(contains('<img')));
    expect(sanitized, isNot(contains('<sub')));
    expect(sanitized, isNot(contains('<!--')));
    expect(
      sanitized,
      contains(
        '![Pullfrog](https://pullfrog.com/logos/frog-white-full-18px.png)',
      ),
    );
    expect(sanitized, contains('[View workflow run](https://example.com/run)'));
    expect(sanitized, contains('[Pullfrog](https://pullfrog.com)'));
  });

  test('preserves task list markers in order', () {
    const body = '- [ ] First <b>bold</b>\n- [x] Second';
    final sanitized = sanitizePullRequestCommentBody(body);

    expect(sanitized.indexOf('[ ]'), isNonNegative);
    expect(sanitized.indexOf('[ ]') < sanitized.indexOf('[x]'), isTrue);
  });
}
