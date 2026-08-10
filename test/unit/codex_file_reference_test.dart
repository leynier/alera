import 'package:alera/src/features/codex_chat/domain/codex_file_reference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats Codex file references like the native composer', () {
    expect(codexFileReferenceText('lib/main.dart'), 'lib/main.dart');
    expect(codexFileReferenceText('docs/file name.md'), '"docs/file name.md"');
    expect(
      codexFileReferenceText('docs/file "quoted".md'),
      'docs/file "quoted".md',
    );
  });

  test('finds the inserted duplicate nearest its recorded offset', () {
    const text = 'docs/readme.md before docs/readme.md after';
    final range = codexFileReferenceRange(
      text,
      'docs/readme.md',
      preferredStart: 22,
    );

    expect(range, isNotNull);
    expect(text.substring(range!.start, range.end), 'docs/readme.md ');
    expect(
      text.replaceRange(range.start, range.end, ''),
      'docs/readme.md before after',
    );
  });
}
