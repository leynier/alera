import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_transcript_assembler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stitches repeated segment boundaries once', () {
    final assembler = MobileAiDictationTranscriptAssembler()
      ..add('The deployment is ready for')
      ..add('ready for production tomorrow.');

    expect(assembler.text, 'The deployment is ready for production tomorrow.');
  });

  test('keeps only a bounded prompt from a long transcript', () {
    final assembler = MobileAiDictationTranscriptAssembler()
      ..add(List<String>.filled(100, 'word').join(' '));

    expect(assembler.prompt.length, lessThanOrEqualTo(240));
  });
}
