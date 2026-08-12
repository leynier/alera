import 'package:alera/src/features/browser/domain/browser_annotation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  });
}
