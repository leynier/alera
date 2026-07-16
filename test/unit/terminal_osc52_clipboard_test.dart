import 'dart:convert';

import 'package:alera/src/features/workbench/domain/terminal_osc52_clipboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes valid OSC 52 writes', () {
    final payload = base64.encode(utf8.encode('copied text'));

    final request = parseTerminalOsc52Request(<String>['cp', payload]);

    expect(request, isA<TerminalOsc52Write>());
    expect((request as TerminalOsc52Write).text, 'copied text');
    expect(
      parseTerminalOsc52Request(<String>['s0', payload]),
      isA<TerminalOsc52Write>(),
    );
    expect(
      (parseTerminalOsc52Request(const <String>['c', '']) as TerminalOsc52Write)
          .text,
      isEmpty,
    );
  });

  test('recognizes queries without exposing clipboard contents', () {
    expect(
      parseTerminalOsc52Request(const <String>['c', '?']),
      isA<TerminalOsc52Query>(),
    );
  });

  test('rejects malformed and oversized OSC 52 payloads', () {
    expect(
      parseTerminalOsc52Request(const <String>['', 'YQ==']),
      isA<TerminalOsc52Invalid>(),
    );
    expect(
      parseTerminalOsc52Request(const <String>['c', 'not base64']),
      isA<TerminalOsc52Invalid>(),
    );
    expect(
      parseTerminalOsc52Request(const <String>['c', '====']),
      isA<TerminalOsc52Invalid>(),
    );
    expect(
      parseTerminalOsc52Request(<String>[
        'c',
        'A' * (terminalOsc52MaxPayloadCharacters + 1),
      ]),
      isA<TerminalOsc52Invalid>(),
    );
  });
}
