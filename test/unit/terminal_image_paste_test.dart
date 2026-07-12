import 'package:alera/src/features/workbench/domain/terminal_image_paste.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sanitizes image paths without shell quoting', () {
    const path =
        r'C:\Users\Alera User\Temp\image $&'
        '".png';

    expect(sanitizeTerminalImagePastePath(path), path);
    expect(
      sanitizeTerminalImagePastePath('/tmp/before\x1b[201~after.png'),
      '/tmp/before\u241b[201~after.png',
    );
  });
}
