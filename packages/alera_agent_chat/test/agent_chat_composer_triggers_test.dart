import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

/// The trigger in [text] with the caret where `|` is.
AgentChatComposerTrigger? _at(String text) {
  final caret = text.indexOf('|');
  return agentChatComposerTriggerAt(
    text.replaceFirst('|', ''),
    selectionStart: caret,
    selectionEnd: caret,
  );
}

void main() {
  test('an @ at a word start and a leading / open the menu', () {
    expect(
      _at('see @src/ma|in'),
      const AgentChatComposerTrigger(
        kind: AgentChatComposerTriggerKind.mention,
        query: 'src/ma',
        start: 4,
        end: 13,
      ),
    );
    expect(
      _at('/com|'),
      const AgentChatComposerTrigger(
        kind: AgentChatComposerTriggerKind.command,
        query: 'com',
        start: 0,
        end: 4,
      ),
    );
  });

  test('a / at a later word start opens commands, as in T3 Code', () {
    expect(
      _at('fix /mod|'),
      const AgentChatComposerTrigger(
        kind: AgentChatComposerTriggerKind.command,
        query: 'mod',
        start: 4,
        end: 8,
      ),
    );
  });

  test('a path, a slash mid-word, an email and a selection do not', () {
    expect(_at('open src/ma|'), isNull);
    expect(_at('open /src/ma|'), isNull);
    expect(_at('open /sr|c/main.dart'), isNull);
    expect(_at('mail me@ho|st'), isNull);
    expect(
      agentChatComposerTriggerAt('/mo', selectionStart: 0, selectionEnd: 3),
      isNull,
    );
    expect(
      agentChatComposerTriggerAt('/mo', selectionStart: -1, selectionEnd: -1),
      isNull,
    );
  });

  test('removing a token leaves no double space', () {
    final trigger = _at('look @ma| here')!;
    final replaced = agentChatComposerTriggerReplaced('look @ma here', trigger);
    expect(replaced.text, 'look here');
    expect(replaced.caret, 5);
  });

  test('a replacement ending in a space absorbs the space already there', () {
    final trigger = _at('/rev| the diff')!;
    final replaced = agentChatComposerTriggerReplaced(
      '/rev the diff',
      trigger,
      replacement: '/review ',
    );
    expect(replaced.text, '/review the diff');
    expect(replaced.caret, 8);
    final alone = agentChatComposerTriggerReplaced(
      '/rev',
      _at('/rev|')!,
      replacement: '/review ',
    );
    expect(alone.text, '/review ');
    expect(alone.caret, 8);
  });

  test('a currency sigil at a word start opens skills', () {
    expect(
      _at('use \$rev|iew now'),
      const AgentChatComposerTrigger(
        kind: AgentChatComposerTriggerKind.skill,
        query: 'rev',
        start: 4,
        end: 11,
      ),
    );
    expect(_at('€|')?.kind, AgentChatComposerTriggerKind.skill);
    expect(_at('€|')?.query, '');
    expect(_at('£dep|')?.query, 'dep');
  });

  test('amounts and mid-word sigils do not open skills', () {
    for (final text in <String>[
      r'costs $5|',
      r'costs $10k|',
      r'costs $9.99|',
      r'costs $1e6|',
      r'($5)|',
      r'price$ta|g',
    ]) {
      expect(_at(text), isNull, reason: text);
    }
  });
}
