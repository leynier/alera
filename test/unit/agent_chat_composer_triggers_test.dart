import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_triggers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// [text] with the caret where `|` is.
TextEditingValue _at(String text) {
  final caret = text.indexOf('|');
  return TextEditingValue(
    text: text.replaceFirst('|', ''),
    selection: TextSelection.collapsed(offset: caret),
  );
}

void main() {
  group('mentions', () {
    test('an @ at the start of a word opens with the text after it', () {
      expect(
        detectAgentChatComposerTrigger(_at('look at @src/ma|')),
        const AgentChatComposerTrigger(
          kind: AgentChatComposerTriggerKind.mention,
          query: 'src/ma',
          start: 8,
          end: 15,
        ),
      );
      expect(detectAgentChatComposerTrigger(_at('@|'))?.query, isEmpty);
      expect(
        detectAgentChatComposerTrigger(_at('first line\n@rea|'))?.start,
        11,
      );
    });

    test('the token spans the whole word when the caret is inside it', () {
      final trigger = detectAgentChatComposerTrigger(_at('see @rea|dme now'));
      expect(trigger?.query, 'rea');
      expect(trigger?.start, 4);
      expect(trigger?.end, 11);
    });

    test('an @ inside a word, after a space or with a selection does not', () {
      expect(detectAgentChatComposerTrigger(_at('me@example.com|')), isNull);
      expect(detectAgentChatComposerTrigger(_at('@src |')), isNull);
      expect(detectAgentChatComposerTrigger(_at('plain text|')), isNull);
      expect(
        detectAgentChatComposerTrigger(
          const TextEditingValue(
            text: '@src',
            selection: TextSelection(baseOffset: 1, extentOffset: 4),
          ),
        ),
        isNull,
      );
    });
  });

  group('commands', () {
    test('a slash opens only as the first character of the prompt', () {
      expect(
        detectAgentChatComposerTrigger(_at('/pl|')),
        const AgentChatComposerTrigger(
          kind: AgentChatComposerTriggerKind.command,
          query: 'pl',
          start: 0,
          end: 3,
        ),
      );
      expect(detectAgentChatComposerTrigger(_at('/|'))?.query, isEmpty);
      expect(detectAgentChatComposerTrigger(_at('run /plan|')), isNull);
      expect(detectAgentChatComposerTrigger(_at(' /plan|')), isNull);
      expect(detectAgentChatComposerTrigger(_at('line\n/plan|')), isNull);
      expect(detectAgentChatComposerTrigger(_at('src/main.dart|')), isNull);
    });

    test('the menu closes once the command is followed by a space', () {
      expect(detectAgentChatComposerTrigger(_at('/plan |')), isNull);
    });
  });

  group('replacing', () {
    test('removing a token drops the space after it', () {
      final value = _at('see @rea| please');
      final trigger = detectAgentChatComposerTrigger(value)!;
      final next = replaceAgentChatComposerTrigger(value, trigger);
      expect(next.text, 'see please');
      expect(next.selection, const TextSelection.collapsed(offset: 4));
    });

    test('removing a leading command leaves the rest of the prompt', () {
      final value = _at('/pl| then go');
      final next = replaceAgentChatComposerTrigger(
        value,
        detectAgentChatComposerTrigger(value)!,
      );
      expect(next.text, 'then go');
      expect(next.selection.extentOffset, 0);
      expect(
        replaceAgentChatComposerTrigger(
          _at('/model|'),
          detectAgentChatComposerTrigger(_at('/model|'))!,
        ).text,
        isEmpty,
      );
    });

    test('a replacement keeps the text after the token', () {
      final value = _at('see @rea| please');
      final next = replaceAgentChatComposerTrigger(
        value,
        detectAgentChatComposerTrigger(value)!,
        replacement: 'README.md',
      );
      expect(next.text, 'see README.md please');
      expect(next.selection.extentOffset, 13);
    });
  });
}
