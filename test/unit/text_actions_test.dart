import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_prompt.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/features/text_actions/application/text_action_prompt.dart';
import 'package:alera/src/features/text_actions/application/text_action_replacement.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_mutations.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final first = const TextAction(
    id: 'first',
    name: 'Polish',
    prompt: 'Improve clarity.',
  );
  final second = const TextAction(
    id: 'second',
    name: 'Summarize',
    prompt: 'Summarize the text.',
  );

  test('defaults to an empty action list', () {
    expect(TextActionsSettings.defaults.actions, isEmpty);
  });

  test('validates non-empty and case-insensitive unique names', () {
    expect(
      textActionValidationError(
        const TextAction(id: 'new', name: ' ', prompt: 'prompt'),
        <TextAction>[first],
      ),
      'Action name is required.',
    );
    expect(
      textActionValidationError(
        const TextAction(id: 'new', name: 'POLISH', prompt: 'prompt'),
        <TextAction>[first],
      ),
      'Action names must be unique.',
    );
    expect(
      textActionValidationError(
        const TextAction(id: 'first', name: 'POLISH', prompt: 'prompt'),
        <TextAction>[first],
        editingId: 'first',
      ),
      isNull,
    );
    expect(
      textActionValidationError(
        const TextAction(id: 'first', name: 'New', prompt: 'prompt'),
        <TextAction>[first],
      ),
      'Action IDs must be unique.',
    );
  });

  test('round-trips action overrides and per-model reasoning', () {
    const settings = TextActionsSettings(
      actions: <TextAction>[
        TextAction(
          id: 'translate',
          name: 'Translate',
          prompt: 'Translate to Spanish.',
          enabled: false,
          agentOverride: AiTextGenerationAgent.claude,
          modelOverride: 'claude-sonnet-4-6',
          reasoningByModel: <String, String>{'claude-sonnet-4-6': 'high'},
        ),
      ],
    );

    final decoded = TextActionsSettings.fromJson(settings.toMap());

    expect(decoded.toMap(), settings.toMap());
  });

  test('duplicates with a new id and stable copy name', () {
    final settings = TextActionsSettings(actions: <TextAction>[first, second]);
    final duplicate = TextActionsMutations.duplicate(settings, first);

    expect(duplicate.actions, hasLength(3));
    expect(duplicate.actions[1].name, 'Polish Copy');
    expect(duplicate.actions[1].id, isNot(first.id));
    expect(duplicate.actions[1].prompt, first.prompt);

    final copiedAgain = TextActionsMutations.duplicate(duplicate, first);
    expect(copiedAgain.actions[1].name, 'Polish Copy 2');
  });

  test('updates and deletes actions without disturbing saved order', () {
    final settings = TextActionsSettings(actions: <TextAction>[first, second]);
    final updated = TextActionsMutations.update(
      settings,
      first.copyWith(prompt: 'Updated.'),
    );
    final deleted = TextActionsMutations.delete(updated, second.id);

    expect(updated.actions.map((action) => action.id), <String>[
      'first',
      'second',
    ]);
    expect(deleted.actions.single.prompt, 'Updated.');
  });

  test('filters disabled actions without changing menu order', () {
    final settings = TextActionsSettings(
      actions: <TextAction>[
        first,
        second.copyWith(enabled: false),
        first.copyWith(id: 'third', name: 'Third'),
      ],
    );

    expect(settings.enabledActions.map((action) => action.id), <String>[
      'first',
      'third',
    ]);
  });

  test('reorders the saved action list including the final drop position', () {
    final settings = TextActionsSettings(
      actions: <TextAction>[
        first,
        second,
        first.copyWith(id: 'third', name: 'Third'),
      ],
    );

    final reordered = TextActionsMutations.reorder(settings, 0, 3);

    expect(reordered.actions.map((action) => action.id), <String>[
      'second',
      'third',
      'first',
    ]);
  });

  test('builds a replacement-only prompt with delimited source text', () {
    final prompt = buildTextActionPrompt(
      instruction: 'Polish the prose.',
      selectedText: 'Keep this exact source.',
    );

    expect(prompt, startsWith('Polish the prose.'));
    expect(prompt, contains('--- selected text ---'));
    expect(prompt, contains('Keep this exact source.'));
    expect(prompt, contains('Return only the replacement text.'));
    expect(prompt, isNot(contains('{placeholder}')));
  });

  test('generic cleanup preserves meaningful list markers', () {
    expect(cleanGeneratedText('- Keep the bullet'), '- Keep the bullet');
    expect(cleanGeneratedText('1. Keep the number'), '1. Keep the number');
  });

  test('action reasoning overrides the global model reasoning', () {
    const settings = AiTextGenerationSettings(
      selectedModelByAgent: <AiTextGenerationAgent, String>{
        AiTextGenerationAgent.codex: 'gpt-5.5',
      },
      selectedThinkingByModel: <String, String>{'gpt-5.5': 'low'},
    );
    const action = TextAction(
      id: 'action',
      name: 'Reason',
      prompt: 'Reason.',
      reasoningByModel: <String, String>{'gpt-5.5': 'high'},
    );

    expect(
      action.reasoningFor(settings, model: action.effectiveModel(settings)),
      'high',
    );
  });

  test('action inherits global agent, model, and reasoning by default', () {
    const settings = AiTextGenerationSettings(
      agent: AiTextGenerationAgent.claude,
      selectedModelByAgent: <AiTextGenerationAgent, String>{
        AiTextGenerationAgent.claude: 'claude-sonnet-4-6',
      },
      selectedThinkingByModel: <String, String>{'claude-sonnet-4-6': 'medium'},
    );

    expect(first.effectiveAgent(settings), AiTextGenerationAgent.claude);
    expect(first.effectiveModel(settings), 'claude-sonnet-4-6');
    expect(
      first.reasoningFor(settings, model: first.effectiveModel(settings)),
      'medium',
    );
  });

  test(
    'safe replacement requires an unchanged field and selects the result',
    () {
      const captured = TextEditingValue(
        text: 'Before old after',
        selection: TextSelection(baseOffset: 7, extentOffset: 10),
      );

      expect(
        canApplyTextActionReplacement(
          captured: captured,
          current: captured,
          replacement: 'new words',
        ),
        isTrue,
      );
      expect(
        canApplyTextActionReplacement(
          captured: captured,
          current: captured.copyWith(text: 'Changed'),
          replacement: 'new words',
        ),
        isFalse,
      );
      expect(
        canApplyTextActionReplacement(
          captured: captured,
          current: captured,
          replacement: '  ',
        ),
        isFalse,
      );

      final intent = buildTextActionReplacementIntent(
        captured: captured,
        replacement: 'new words',
      );
      final replaced = intent.currentTextEditingValue.replaced(
        intent.replacementRange,
        intent.replacementText,
      );
      expect(replaced.text, 'Before new words after');
      expect(
        replaced.selection,
        const TextSelection(baseOffset: 7, extentOffset: 16),
      );
    },
  );
}
