import 'package:flutter/foundation.dart';

enum BrowserAnnotationKind { element, region }

@immutable
class BrowserAnnotationElement {
  const BrowserAnnotationElement({required this.anchor});

  final BrowserAnnotationAnchor anchor;
}

@immutable
class BrowserAnnotationAnchor {
  const BrowserAnnotationAnchor({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.role,
    this.name,
    this.tag,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final String? role;
  final String? name;
  final String? tag;

  String get geometry =>
      '${_percent(x)},${_percent(y)},${_percent(width)},${_percent(height)}';

  Map<String, Object?> toJson() => <String, Object?>{
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    if (role != null && role!.isNotEmpty) 'role': role,
    if (name != null && name!.isNotEmpty) 'name': name,
    if (tag != null && tag!.isNotEmpty) 'tag': tag,
  };

  static String _percent(double value) =>
      '${(value.clamp(0.0, 1.0) * 100).toStringAsFixed(1)}%';
}

@immutable
class BrowserAnnotationComment {
  const BrowserAnnotationComment({
    required this.id,
    required this.kind,
    required this.anchor,
    required this.text,
  });

  final String id;
  final BrowserAnnotationKind kind;
  final BrowserAnnotationAnchor anchor;
  final String text;

  BrowserAnnotationComment copyWith({String? text}) => BrowserAnnotationComment(
    id: id,
    kind: kind,
    anchor: anchor,
    text: text ?? this.text,
  );

  Map<String, Object?> toJson({required int index}) => <String, Object?>{
    'index': index,
    'id': id,
    'kind': kind.name,
    'anchor': anchor.toJson(),
    'text': text,
  };
}

@immutable
class BrowserAnnotationCapture {
  const BrowserAnnotationCapture({
    required this.imagePath,
    required this.url,
    required this.title,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.comments,
    required this.capturedAt,
  });

  final String imagePath;
  final Uri url;
  final String title;
  final int viewportWidth;
  final int viewportHeight;
  final List<BrowserAnnotationComment> comments;
  final DateTime capturedAt;

  BrowserAnnotationCapture copyWith({
    List<BrowserAnnotationComment>? comments,
  }) => BrowserAnnotationCapture(
    imagePath: imagePath,
    url: url,
    title: title,
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    comments: comments ?? this.comments,
    capturedAt: capturedAt,
  );

  String get displayName =>
      'Browser Annotation (${comments.length} ${comments.length == 1 ? 'Comment' : 'Comments'})';

  String get contextText {
    final buffer = StringBuffer()
      ..writeln('Browser annotation context')
      ..writeln('Page: ${title.isEmpty ? url.host : title}')
      ..writeln('URL: ${url.toString()}')
      ..writeln('Viewport: ${viewportWidth}x$viewportHeight');
    for (var index = 0; index < comments.length; index++) {
      final comment = comments[index];
      final target = comment.kind == BrowserAnnotationKind.element
          ? _elementTarget(comment.anchor)
          : 'region ${comment.anchor.geometry}';
      buffer
        ..writeln()
        ..writeln('${index + 1}. $target')
        ..writeln('   Comment: ${comment.text}');
    }
    return buffer.toString().trim();
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'imagePath': imagePath,
    'url': url.toString(),
    'title': title,
    'viewportWidth': viewportWidth,
    'viewportHeight': viewportHeight,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'comments': <Map<String, Object?>>[
      for (var index = 0; index < comments.length; index++)
        comments[index].toJson(index: index + 1),
    ],
  };

  static String _elementTarget(BrowserAnnotationAnchor anchor) {
    final role = anchor.role?.trim();
    final name = anchor.name?.trim();
    if (role != null && role.isNotEmpty && name != null && name.isNotEmpty) {
      return 'Element: $role "$name" (${anchor.geometry})';
    }
    if (name != null && name.isNotEmpty) {
      return 'Element: "$name" (${anchor.geometry})';
    }
    return 'Element: ${anchor.tag ?? 'unknown'} (${anchor.geometry})';
  }
}
