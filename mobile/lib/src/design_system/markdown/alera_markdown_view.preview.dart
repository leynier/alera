import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/markdown/alera_markdown_view.dart';
import 'package:flutter/widgets.dart';

const String aleraMarkdownViewPreviewSample = '''
# Workspace Guide

Alera keeps **agents**, terminals, and reviews in one place.

- Read the `AGENTS.md` rules first
- Open the [documentation](https://example.com/docs)

```dart
void main() => print('Hello from Alera');
```
''';

@AleraPreview(name: 'Markdown View', group: 'Markdown')
Widget aleraMarkdownViewPreview() => SingleChildScrollView(
  child: AleraMarkdownView(
    data: aleraMarkdownViewPreviewSample,
    imageBuilder: (_, _, _, _) => const SizedBox.shrink(),
    onLinkTap: (_) {},
  ),
);
