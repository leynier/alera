import 'package:alera_mobile/src/features/workbench/domain/workspace_markdown_uri_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes Markdown files by extension', () {
    expect(isWorkspaceMarkdownPath('readme.md'), isTrue);
    expect(isWorkspaceMarkdownPath('docs/GUIDE.MD'), isTrue);
    expect(isWorkspaceMarkdownPath('pages/index.mdx'), isTrue);
    expect(isWorkspaceMarkdownPath('lib/main.dart'), isFalse);
    expect(isWorkspaceMarkdownPath('notes.md.txt'), isFalse);
  });

  test('link policy only accepts web URLs with hosts', () {
    expect(
      isSupportedMarkdownViewerLinkUri(Uri.parse('https://example.com/docs')),
      isTrue,
    );
    expect(
      isSupportedMarkdownViewerLinkUri(Uri.parse('http://example.com')),
      isTrue,
    );
    for (final raw in <String>[
      'file:///tmp/readme.md',
      'mailto:test@example.com',
      'javascript:alert(1)',
      'vscode://file/foo',
      'https:///missing-host',
      'docs/readme.md',
    ]) {
      expect(isSupportedMarkdownViewerLinkUri(Uri.tryParse(raw)), isFalse);
    }
    expect(isSupportedMarkdownViewerLinkUri(null), isFalse);
  });

  test('remote image policy only accepts web URLs with hosts', () {
    expect(
      isSupportedMarkdownViewerRemoteImageUri(
        Uri.parse('https://example.com/diagram.png'),
      ),
      isTrue,
    );
    expect(
      isSupportedMarkdownViewerRemoteImageUri(
        Uri.parse('file:///tmp/diagram.png'),
      ),
      isFalse,
    );
    expect(
      isSupportedMarkdownViewerRemoteImageUri(
        Uri.parse('data:image/png;base64,AAAA'),
      ),
      isFalse,
    );
  });

  test('resolves relative images inside the workspace only', () {
    String? resolve(String markdownPath, String rawImageUrl) =>
        resolveWorkspaceMarkdownImagePath(
          markdownPath: markdownPath,
          rawImageUrl: rawImageUrl,
        );

    expect(resolve('readme.md', 'diagram.png'), 'diagram.png');
    expect(
      resolve('docs/readme.md', './images/diagram.png'),
      'docs/images/diagram.png',
    );
    expect(
      resolve('docs/guides/readme.md', '../assets/diagram.png'),
      'docs/assets/diagram.png',
    );
    expect(resolve('docs/readme.md', 'my%20image.png'), 'docs/my image.png');
    expect(resolve('docs/readme.md', '../../secret.png'), isNull);
    expect(resolve('readme.md', '..'), isNull);
    expect(resolve('docs/readme.md', '/etc/secret.png'), isNull);
    expect(resolve('docs/readme.md', '//host/secret.png'), isNull);
    expect(resolve('docs/readme.md', r'\secret.png'), isNull);
    expect(resolve('docs/readme.md', r'C:\secret.png'), isNull);
    expect(resolve('docs/readme.md', 'file:///tmp/secret.png'), isNull);
    expect(resolve('docs/readme.md', 'diagram.png?raw=1'), isNull);
    expect(resolve('docs/readme.md', 'diagram.png#top'), isNull);
    expect(resolve('docs/readme.md', '   '), isNull);
  });
}
