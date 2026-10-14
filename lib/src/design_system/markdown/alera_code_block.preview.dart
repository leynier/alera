import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/markdown/alera_code_block.dart';
import 'package:flutter/material.dart';

const String _sampleCode = '''
void main() {
  final greeting = 'Hello from Alera';
  print(greeting);
}''';

@AleraPreview(name: 'With language', group: 'Code Block', size: Size(520, 200))
Widget aleraCodeBlockPreview() =>
    const AleraCodeBlock(code: _sampleCode, language: 'dart');

@AleraPreview(
  name: 'Without language',
  group: 'Code Block',
  size: Size(520, 160),
)
Widget aleraCodeBlockPlainPreview() => const AleraCodeBlock(
  code:
      r'$ make app-debug'
      '\nBuilding Alera Dev…',
);

@AleraPreview(name: 'Highlighted', group: 'Code Block', size: Size(520, 200))
Widget aleraCodeBlockHighlightedPreview() => const AleraCodeBlock(
  code: _sampleCode,
  language: 'dart',
  highlighted: TextSpan(
    children: <InlineSpan>[
      TextSpan(
        text: 'void ',
        style: TextStyle(color: AleraTokens.syntaxKeyword),
      ),
      TextSpan(
        text: 'main',
        style: TextStyle(color: AleraTokens.syntaxFunction),
      ),
      TextSpan(text: '() {\n  '),
      TextSpan(
        text: 'final ',
        style: TextStyle(color: AleraTokens.syntaxKeyword),
      ),
      TextSpan(text: 'greeting = '),
      TextSpan(
        text: "'Hello from Alera'",
        style: TextStyle(color: AleraTokens.syntaxLiteral),
      ),
      TextSpan(text: ';\n  '),
      TextSpan(
        text: 'print',
        style: TextStyle(color: AleraTokens.syntaxFunction),
      ),
      TextSpan(text: '(greeting);\n}'),
    ],
  ),
);

@AleraPreview(name: 'No header', group: 'Code Block', size: Size(520, 120))
Widget aleraCodeBlockNoHeaderPreview() =>
    const AleraCodeBlock(code: 'exit status 0', showCopy: false);
