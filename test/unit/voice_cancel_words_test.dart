import 'package:alera/src/features/voice/infra/voice_audio_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home cancel words match the host list', () {
    expect(looksLikeHomeCancel('Para'), isTrue);
    expect(looksLikeHomeCancel('  cállate '), isTrue);
    expect(looksLikeHomeCancel('Stop.'), isTrue);
    expect(looksLikeHomeCancel('¡Para!'), isTrue);
    expect(looksLikeHomeCancel('(Stop)'), isTrue);
    expect(looksLikeHomeCancel('please stop the build'), isFalse);
  });
}
