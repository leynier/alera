import 'dart:convert';

import 'package:alera/src/features/workbench/domain/terminal_agent_prompt_injection.dart';
import 'package:alera/src/features/workbench/domain/terminal_submit_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildTerminalSubmitPayloadBytes', () {
    test('returns raw UTF-8 when bracketed paste mode is off', () {
      final bytes = buildTerminalSubmitPayloadBytes(
        'Review this change',
        bracketedPasteMode: false,
      );

      expect(utf8.decode(bytes), 'Review this change');
      expect(bytes, isNot(contains(0x1b)));
    });

    test('wraps payload in bracketed paste markers when mode is on', () {
      final bytes = buildTerminalSubmitPayloadBytes(
        'Review this change',
        bracketedPasteMode: true,
      );
      final text = utf8.decode(bytes);

      expect(text, startsWith(terminalBracketedPasteStart));
      expect(text, endsWith(terminalBracketedPasteEnd));
      expect(text, contains('Review this change'));
      expect(
        text,
        '$terminalBracketedPasteStart'
        'Review this change'
        '$terminalBracketedPasteEnd',
      );
    });

    test('preserves non-ASCII text in both modes', () {
      const prompt = 'hello λ world';
      expect(
        utf8.decode(
          buildTerminalSubmitPayloadBytes(prompt, bracketedPasteMode: false),
        ),
        prompt,
      );
      expect(
        utf8.decode(
          buildTerminalSubmitPayloadBytes(prompt, bracketedPasteMode: true),
        ),
        '$terminalBracketedPasteStart$prompt$terminalBracketedPasteEnd',
      );
    });

    test('preserves multiline text without rewriting controls', () {
      const prompt = 'line one\nline two\ttrail';
      expect(
        utf8.decode(
          buildTerminalSubmitPayloadBytes(prompt, bracketedPasteMode: false),
        ),
        prompt,
      );
      expect(
        utf8.decode(
          buildTerminalSubmitPayloadBytes(prompt, bracketedPasteMode: true),
        ),
        '$terminalBracketedPasteStart$prompt$terminalBracketedPasteEnd',
      );
    });
  });
}
