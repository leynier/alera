String buildTextActionPrompt({
  required String instruction,
  required String selectedText,
}) {
  return <String>[
    instruction.trim(),
    '',
    'Replace only the selected text using the source below.',
    '--- selected text ---',
    selectedText,
    '--- end selected text ---',
    '',
    'Return only the replacement text. Do not include explanations or code fences.',
  ].join('\n');
}
