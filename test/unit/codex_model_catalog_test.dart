import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot contains only expected visible models in order', () {
    final ids = codexModelSnapshot.map((model) => model.id).toList();

    expect(ids, <String>[
      'gpt-5.5',
      'gpt-5.4',
      'gpt-5.4-mini',
      'gpt-5.3-codex',
      'gpt-5.3-codex-spark',
      'gpt-5.2-codex',
      'gpt-5.2',
      'gpt-5.1-codex-max',
      'gpt-5.1-codex-mini',
    ]);
    expect(codexDefaultModelId(), 'gpt-5.2-codex');
  });

  test('reasoning effort support and closest mapping follow model rules', () {
    expect(supportedReasoningEffortsForModel('gpt-5.1-codex-mini'), <String>[
      'medium',
      'high',
    ]);
    expect(supportedReasoningEffortsForModel('gpt-5.3-codex'), <String>[
      'low',
      'medium',
      'high',
      'xhigh',
    ]);

    expect(
      closestSupportedReasoningEffort(
        modelId: 'gpt-5.1-codex-mini',
        effort: 'low',
      ),
      'medium',
    );
    expect(
      closestSupportedReasoningEffort(
        modelId: 'gpt-5.1-codex-mini',
        effort: 'xhigh',
      ),
      'high',
    );
    expect(
      closestSupportedReasoningEffort(
        modelId: 'gpt-5.3-codex',
        effort: 'xhigh',
      ),
      'xhigh',
    );
  });

  test('fast speed mode is limited to supported models', () {
    expect(supportedSpeedModesForModel('gpt-5.5'), <String>['normal', 'fast']);
    expect(supportedSpeedModesForModel('gpt-5.4'), <String>['normal', 'fast']);
    expect(supportedSpeedModesForModel('gpt-5.4-mini'), <String>['normal']);
    expect(supportedSpeedModesForModel('gpt-5.3-codex'), <String>['normal']);

    expect(
      closestSupportedSpeedMode(modelId: 'gpt-5.5', speedMode: 'fast'),
      'fast',
    );
    expect(
      closestSupportedSpeedMode(modelId: 'gpt-5.3-codex', speedMode: 'fast'),
      'normal',
    );
  });
}
