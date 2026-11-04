import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/markdown/alera_markdown_view.dart';
import 'package:flutter/material.dart';

const String _sampleDocument = '''
# Release Notes

Alera keeps **agents**, terminals, and reviews in one place. Run `make app-debug` to try a local build.

## What Changed

- Streaming labels share one paced shimmer
- Code blocks scroll sideways and offer Copy
- Links go through the caller, like the [documentation](https://example.com/docs)

```dart
void main() {
  print('Hello from Alera');
}
```
''';

const String _streamingDocument = '''
### Plan

1. Read the failing test
2. Patch the parser

```sh
make rust-test
cargo test --workspace''';

@AleraPreview(name: 'Document', group: 'Markdown', size: Size(560, 520))
Widget aleraMarkdownViewPreview() => SingleChildScrollView(
  child: AleraMarkdownView(data: _sampleDocument, onLinkTap: (_) {}),
);

@AleraPreview(name: 'Unclosed fence', group: 'Markdown', size: Size(560, 320))
Widget aleraMarkdownViewStreamingPreview() => const SingleChildScrollView(
  child: AleraMarkdownView(data: _streamingDocument),
);
