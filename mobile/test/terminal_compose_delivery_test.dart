import 'dart:convert';

import 'package:alera_mobile/src/features/terminal/domain/terminal_compose_delivery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Host supports deferred input', () {
    test('A single-line prompt defers the Enter without pasting', () {
      final delivery = TerminalComposeDelivery.forText(
        'ls -la',
        withEnter: true,
        hostSupportsDeferredInput: true,
      );

      // The CR is not in the payload: the host writes it separately, which is
      // the whole point. A short command is not pasted, because agent TUIs
      // collapse a paste into a placeholder and programs without DECSET 2004
      // leak the markers as literal text.
      expect(delivery.bytes, utf8.encode('ls -la'));
      expect(delivery.bracketedPaste, isFalse);
      expect(delivery.deferredEnter, isTrue);
    });

    test('An empty send asks the host for a bare Enter', () {
      final delivery = TerminalComposeDelivery.forText(
        '',
        withEnter: true,
        hostSupportsDeferredInput: true,
      );

      expect(delivery.bytes, isEmpty);
      expect(delivery.deferredEnter, isTrue);
      expect(delivery.bracketedPaste, isFalse);
    });

    test('Sending without Enter carries neither flag', () {
      final delivery = TerminalComposeDelivery.forText(
        'ls -la',
        withEnter: false,
        hostSupportsDeferredInput: true,
      );

      expect(delivery.bytes, utf8.encode('ls -la'));
      expect(delivery.deferredEnter, isFalse);
      expect(delivery.bracketedPaste, isFalse);
    });

    test('Multi-line text is pasted so LFs are not accept-line', () {
      final delivery = TerminalComposeDelivery.forText(
        'first\nsecond',
        withEnter: true,
        hostSupportsDeferredInput: true,
      );

      expect(delivery.bytes, utf8.encode('first\nsecond'));
      expect(delivery.bracketedPaste, isTrue);
      expect(delivery.deferredEnter, isTrue);
    });
  });

  group('Host without deferred input', () {
    test('Falls back to one write with the CR appended', () {
      final delivery = TerminalComposeDelivery.forText(
        'ls -la',
        withEnter: true,
        hostSupportsDeferredInput: false,
      );

      expect(delivery.bytes, utf8.encode('ls -la\r'));
      expect(delivery.bracketedPaste, isFalse);
      expect(delivery.deferredEnter, isFalse);
    });

    test('An empty send is just the CR', () {
      final delivery = TerminalComposeDelivery.forText(
        '',
        withEnter: true,
        hostSupportsDeferredInput: false,
      );

      expect(delivery.bytes, utf8.encode('\r'));
      expect(delivery.deferredEnter, isFalse);
    });
  });

  group('Bracketed paste predicate', () {
    test('Plain single-line text does not need it', () {
      expect(composedTextNeedsBracketedPaste('git status'), isFalse);
      expect(composedTextNeedsBracketedPaste(''), isFalse);
      expect(composedTextNeedsBracketedPaste('a' * 512), isFalse);
    });

    test('Control characters and long text need it', () {
      expect(composedTextNeedsBracketedPaste('a\nb'), isTrue);
      expect(composedTextNeedsBracketedPaste('a\tb'), isTrue);
      expect(composedTextNeedsBracketedPaste('a\x1bb'), isTrue);
      expect(composedTextNeedsBracketedPaste('a\x7fb'), isTrue);
      expect(composedTextNeedsBracketedPaste('a' * 513), isTrue);
    });
  });
}
