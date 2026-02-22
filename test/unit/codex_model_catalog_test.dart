import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot contains only expected visible models in order', () {
    final ids = codexModelSnapshot.map((model) => model.id).toList();

    expect(ids, <String>[
      'gpt-5.2-codex',
      'gpt-5.3-codex',
      'gpt-5.1-codex-max',
      'gpt-5.1-codex-mini',
      'gpt-5.2',
    ]);
    expect(codexDefaultModelId(), 'gpt-5.2-codex');
  });
}
