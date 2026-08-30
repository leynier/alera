import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_comment_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('comment links only allow web URLs with hosts', () {
    expect(
      isSupportedPullRequestCommentLinkUri(
        Uri.parse('https://example.com/docs'),
      ),
      isTrue,
    );
    expect(
      isSupportedPullRequestCommentLinkUri(Uri.parse('http://example.com')),
      isTrue,
    );
    expect(
      isSupportedPullRequestCommentLinkUri(Uri.parse('file:///tmp/readme.md')),
      isFalse,
    );
    expect(
      isSupportedPullRequestCommentLinkUri(
        Uri.parse('mailto:test@example.com'),
      ),
      isFalse,
    );
    expect(
      isSupportedPullRequestCommentLinkUri(Uri.tryParse('docs/readme.md')),
      isFalse,
    );
  });

  test('comment images only allow HTTPS URLs with hosts', () {
    expect(
      isSupportedPullRequestCommentImageUri(
        Uri.parse('https://example.com/diagram.png'),
      ),
      isTrue,
    );
    expect(
      isSupportedPullRequestCommentImageUri(
        Uri.parse('http://example.com/diagram.png'),
      ),
      isFalse,
    );
    expect(
      isSupportedPullRequestCommentImageUri(
        Uri.parse('file:///tmp/diagram.png'),
      ),
      isFalse,
    );
    expect(
      isSupportedPullRequestCommentImageUri(
        Uri.parse('data:image/png;base64,AA=='),
      ),
      isFalse,
    );
  });

  testWidgets('renders formatted text, lists, and fenced code', (tester) async {
    await tester.pumpWidget(
      _surface('''
**Important**

- First item
- Second item

```dart
final value = 1;
```
'''),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.textContaining('Important'), findsOneWidget);
    expect(find.textContaining('**Important**'), findsNothing);
    expect(find.textContaining('First item'), findsOneWidget);
    expect(find.text('dart'), findsOneWidget);
    expect(find.textContaining('final value = 1;'), findsOneWidget);
  });

  testWidgets('opens supported links and ignores unsupported links', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _surface(
        '[Docs](https://example.com/docs)\n\n'
        '[Local](file:///tmp/readme.md)',
        onOpenUrl: (url) async => opened.add(url),
      ),
    );

    await tester.tap(find.text('Docs'));
    await tester.pump();
    await tester.tap(find.text('Local'));
    await tester.pump();

    expect(opened, <String>['https://example.com/docs']);
  });

  testWidgets('loads HTTPS images and marks blocked or failed images', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: <Widget>[
                buildPullRequestCommentImage(
                  context,
                  'https://example.com/diagram.png',
                  999,
                  999,
                ),
                buildPullRequestCommentImage(
                  context,
                  'http://example.com/blocked.png',
                  null,
                  null,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final imageFinder = find.byType(Image);
    expect(imageFinder, findsOneWidget);
    final image = tester.widget<Image>(imageFinder);
    expect(image.image, isA<NetworkImage>());
    expect(
      (image.image as NetworkImage).url,
      'https://example.com/diagram.png',
    );
    expect(image.width, 400);
    expect(image.height, 300);
    expect(find.byIcon(AleraIcons.imageError), findsOneWidget);

    final errorWidget = image.errorBuilder!(
      tester.element(imageFinder),
      StateError('network failed'),
      .empty,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: errorWidget)));

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(AleraIcons.imageError), findsOneWidget);
  });
}

Widget _surface(String body, {Future<void> Function(String url)? onOpenUrl}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 420,
        child: PullRequestCommentMarkdown(
          body: body,
          onOpenUrl: onOpenUrl ?? (_) async {},
        ),
      ),
    ),
  );
}
