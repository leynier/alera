import 'dart:async';
import 'dart:io';

import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_operation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disposal blocks an async finalization continuation', () async {
    final operation = MobileAiDictationOperation();
    final generation = operation.begin();
    final gap = Completer<void>();
    var committed = false;

    final continuation = () async {
      await gap.future;
      if (operation.isCurrent(generation)) committed = true;
    }();

    operation.dispose();
    gap.complete();
    await continuation;

    expect(committed, isFalse);
  });

  test('disposal blocks a late speech recognition callback', () {
    final operation = MobileAiDictationOperation();
    final generation = operation.begin();
    var committed = false;

    void onSpeechError() {
      if (operation.isCurrent(generation)) committed = true;
    }

    operation.dispose();
    onSpeechError();

    expect(committed, isFalse);
  });

  test('a replacement operation cannot revive an older callback', () {
    final operation = MobileAiDictationOperation();
    final oldGeneration = operation.begin();

    operation.cancel();
    final currentGeneration = operation.begin();

    expect(operation.isCurrent(oldGeneration), isFalse);
    expect(operation.isCurrent(currentGeneration), isTrue);
  });

  test('the disposal callback does not access ref', () async {
    final source = await File(
      'lib/src/features/ai_dictation/application/mobile_ai_dictation_controller.dart',
    ).readAsString();
    final lifecycleSource = await File(
      'lib/src/features/ai_dictation/application/mobile_ai_dictation_controller_lifecycle.dart',
    ).readAsString();
    final callback = source
        .split('ref.onDispose(() {')[1]
        .split('    });\n    return const MobileAiDictationState();')[0];

    expect(callback, isNot(contains('ref.')));
    expect(
      lifecycleSource,
      contains('ref.mounted && _operation.isCurrent(generation)'),
    );
  });
}
