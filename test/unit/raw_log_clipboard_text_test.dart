import 'package:alera/src/features/shell/presentation/alera_shell_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildRawLogClipboardText joins logs in oldest to newest order', () {
    const logs = <String>['event one', 'event two', 'event three'];
    final text = buildRawLogClipboardText(logs);
    expect(text, 'event one\nevent two\nevent three');
  });

  test('buildRawLogClipboardText returns empty string for empty list', () {
    final text = buildRawLogClipboardText(const <String>[]);
    expect(text, isEmpty);
  });
}
