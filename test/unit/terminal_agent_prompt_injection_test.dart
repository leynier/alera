import 'dart:convert';

import 'package:alera/src/features/workbench/domain/terminal_agent_prompt_injection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeAgentPromptText', () {
    test('leaves plain text unchanged', () {
      expect(sanitizeAgentPromptText('hello'), 'hello');
    });

    test('preserves printable Unicode and supported whitespace', () {
      expect(sanitizeAgentPromptText('hello λ\n\tworld'), 'hello λ\n\tworld');
    });

    test('renders every unsafe terminal control', () {
      for (final codePoint in <int>[
        ...List<int>.generate(32, (i) => i),
        0x7f,
      ]) {
        final input = String.fromCharCodes(<int>[0x61, codePoint, 0x62]);
        final expected = codePoint == 0x0a || codePoint == 0x09
            ? input
            : 'a<0x${codePoint.toRadixString(16).toUpperCase().padLeft(2, '0')}>b';
        expect(sanitizeAgentPromptText(input), expected);
      }
    });
  });

  group('buildAgentPromptPasteBytes', () {
    test('wraps sanitized payload in bracketed paste markers', () {
      final bytes = buildAgentPromptPasteBytes('hello\nworld');
      final text = String.fromCharCodes(bytes);
      expect(text.startsWith(terminalBracketedPasteStart), isTrue);
      expect(text.endsWith(terminalBracketedPasteEnd), isTrue);
      expect(text.contains('hello\nworld'), isTrue);
      final inner = bytes.sublist(
        terminalBracketedPasteStart.length,
        bytes.length - terminalBracketedPasteEnd.length,
      );
      expect(
        inner.where((byte) => byte < 0x20 && byte != 0x0a && byte != 0x09),
        isEmpty,
      );
    });
  });

  group('startup command delivery', () {
    test('uses a conservative bracketed-paste shell allowlist', () {
      expect(terminalShellSupportsBracketedPaste('/bin/bash'), isTrue);
      expect(terminalShellSupportsBracketedPaste('/usr/local/bin/zsh'), isTrue);
      expect(terminalShellSupportsBracketedPaste('/usr/bin/fish'), isTrue);
      expect(terminalShellSupportsBracketedPaste('/bin/dash'), isFalse);
      expect(terminalShellSupportsBracketedPaste('/bin/sh'), isFalse);
      expect(
        terminalShellSupportsBracketedPaste(r'C:\Windows\System32\cmd.exe'),
        isFalse,
      );
    });

    test('plain input has exactly one active control: final submit', () {
      final bytes = buildPlainStartupCommandBytes('echo a\x1b\necho\tb\x03');
      final text = utf8.decode(bytes);

      expect(text, 'echo a<0x1B><LF>echo<TAB>b<0x03>\r');
      expect(bytes.where((byte) => byte < 0x20), <int>[0x0d]);
      expect(text, isNot(contains(terminalBracketedPasteStart)));
      expect(text, isNot(contains(terminalBracketedPasteEnd)));
    });
  });

  group('shouldUseBracketedPasteForStartupCommand', () {
    test('is false for short single-line commands', () {
      expect(shouldUseBracketedPasteForStartupCommand('claude'), isFalse);
    });

    test('is true for multiline commands', () {
      expect(
        shouldUseBracketedPasteForStartupCommand('claude\n--flag'),
        isTrue,
      );
    });

    test('is true when ESC is present', () {
      expect(shouldUseBracketedPasteForStartupCommand('x\x1by'), isTrue);
    });
  });
}
