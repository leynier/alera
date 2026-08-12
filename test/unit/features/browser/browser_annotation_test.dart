import 'package:alera/src/features/browser/domain/browser_annotation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes anchors and preserves comment copies', () {
    const anchor = BrowserAnnotationAnchor(
      x: -0.2,
      y: 0.4,
      width: 1.4,
      height: 0.5,
      role: 'button',
      name: 'Save',
      tag: 'button',
    );
    expect(anchor.geometry, '0.0%,40.0%,100.0%,50.0%');
    expect(anchor.toJson(), <String, Object?>{
      'x': -0.2,
      'y': 0.4,
      'width': 1.4,
      'height': 0.5,
      'role': 'button',
      'name': 'Save',
      'tag': 'button',
    });
    expect(const BrowserAnnotationElement(anchor: anchor).anchor, anchor);

    const comment = BrowserAnnotationComment(
      id: 'comment',
      kind: BrowserAnnotationKind.element,
      anchor: anchor,
      text: 'Old text',
    );
    expect(comment.copyWith(text: 'New text').text, 'New text');
    expect(comment.copyWith().text, 'Old text');
    expect(comment.toJson(index: 3)['index'], 3);
  });

  group('BrowserAnnotationCapture', () {
    test('builds structured context for element and region comments', () {
      final capture = BrowserAnnotationCapture(
        imagePath: r'C:\temp\annotation.png',
        url: Uri.parse('https://example.com/docs'),
        title: 'Example docs',
        viewportWidth: 1280,
        viewportHeight: 720,
        capturedAt: DateTime.utc(2026, 8, 12),
        comments: const <BrowserAnnotationComment>[
          BrowserAnnotationComment(
            id: 'element-comment',
            kind: BrowserAnnotationKind.element,
            anchor: BrowserAnnotationAnchor(
              x: 0.125,
              y: 0.25,
              width: 0.5,
              height: 0.1,
              role: 'button',
              name: 'Save',
              tag: 'button',
            ),
            text: 'Use the primary action style.',
          ),
          BrowserAnnotationComment(
            id: 'region-comment',
            kind: BrowserAnnotationKind.region,
            anchor: BrowserAnnotationAnchor(
              x: 0.1,
              y: 0.2,
              width: 0.3,
              height: 0.4,
            ),
            text: 'Increase the spacing here.',
          ),
        ],
      );

      expect(capture.displayName, 'Browser Annotation (2 Comments)');
      expect(
        capture.contextText,
        allOf(
          contains('Page: Example docs'),
          contains('URL: https://example.com/docs'),
          contains('Viewport: 1280x720'),
          contains('Element: button "Save" (12.5%,25.0%,50.0%,10.0%)'),
          contains('region 10.0%,20.0%,30.0%,40.0%'),
          contains('Use the primary action style.'),
        ),
      );
    });

    test('serializes comments with stable indexes and metadata', () {
      final capture = BrowserAnnotationCapture(
        imagePath: '/tmp/annotation.png',
        url: Uri.parse('https://example.com'),
        title: '',
        viewportWidth: 1,
        viewportHeight: 1,
        capturedAt: DateTime.utc(2026, 8, 12),
        comments: const <BrowserAnnotationComment>[
          BrowserAnnotationComment(
            id: 'comment',
            kind: BrowserAnnotationKind.region,
            anchor: BrowserAnnotationAnchor(x: 0, y: 0, width: 1, height: 1),
            text: 'Review this area.',
          ),
        ],
      );

      final json = capture.toJson();
      expect(capture.displayName, 'Browser Annotation (1 Comment)');
      expect(json['url'], 'https://example.com');
      expect(json['capturedAt'], '2026-08-12T00:00:00.000Z');
      expect((json['comments'] as List).single, <String, Object?>{
        'index': 1,
        'id': 'comment',
        'kind': 'region',
        'anchor': <String, Object?>{'x': 0, 'y': 0, 'width': 1, 'height': 1},
        'text': 'Review this area.',
      });
    });

    test(
      'uses fallback element labels and supports empty and copied captures',
      () {
        const anchors = <BrowserAnnotationAnchor>[
          BrowserAnnotationAnchor(x: 0, y: 0, width: 0, height: 0),
          BrowserAnnotationAnchor(
            x: 0,
            y: 0,
            width: 0,
            height: 0,
            name: 'Settings',
          ),
          BrowserAnnotationAnchor(
            x: 0,
            y: 0,
            width: 0,
            height: 0,
            tag: 'section',
          ),
        ];
        final capture = BrowserAnnotationCapture(
          imagePath: '/tmp/annotation.png',
          url: Uri.parse('https://example.com'),
          title: '',
          viewportWidth: 1,
          viewportHeight: 1,
          capturedAt: DateTime.utc(2026, 8, 12),
          comments: <BrowserAnnotationComment>[
            for (var index = 0; index < anchors.length; index++)
              BrowserAnnotationComment(
                id: '$index',
                kind: BrowserAnnotationKind.element,
                anchor: anchors[index],
                text: 'Comment $index',
              ),
          ],
        );
        expect(capture.displayName, 'Browser Annotation (3 Comments)');
        expect(capture.contextText, contains('Element: unknown'));
        expect(capture.contextText, contains('Element: "Settings"'));
        expect(capture.contextText, contains('Element: section'));

        final empty = capture.copyWith(comments: const []);
        expect(empty.displayName, 'Browser Annotation (0 Comments)');
        expect(empty.contextText, contains('Page: example.com'));
        expect(capture.copyWith().comments, capture.comments);
      },
    );
  });
}
