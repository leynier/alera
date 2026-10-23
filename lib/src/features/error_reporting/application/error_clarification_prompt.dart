import 'package:alera/src/features/ai_assist/application/ai_assist_prompt.dart';

/// The longest error text sent to the model. Longer text is cut, and the
/// original is still the fallback, so nothing is lost.
const int errorClarificationInputLimit = 4000;

/// A clarified message longer than this is treated as a failed rewrite.
const int errorClarificationOutputLimit = 600;

String buildErrorClarificationPrompt(String errorMessage) {
  return <String>[
    'Rewrite the error message below, shown to a developer by the Alera desktop app, so it says clearly what went wrong and, when the error supports it, what to do next.',
    '',
    'Rules:',
    '- Reply with the rewritten message only: plain text, no Markdown, no quotes, no preamble.',
    '- Use at most three short sentences in sentence case.',
    '- Keep every concrete detail that matters: file paths, branch names, commands, exit codes, and the underlying cause.',
    '- Do not invent causes, settings, or steps the error does not support.',
    '- If the message is already clear, return it unchanged.',
    '',
    'Error message:',
    '<<<',
    limitPromptSection(errorMessage.trim(), errorClarificationInputLimit),
    '>>>',
  ].join('\n');
}

/// The rewritten message, or null when the model's answer is unusable and the
/// original error must be shown instead.
String? parseErrorClarification(String raw) {
  var text = cleanGeneratedText(raw).trim();
  if (text.length >= 2) {
    final first = text[0];
    final last = text[text.length - 1];
    if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
      text = text.substring(1, text.length - 1).trim();
    }
  }
  text = text.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
  if (text.isEmpty ||
      text.length > errorClarificationOutputLimit ||
      text.contains('<<<') ||
      text.contains('>>>')) {
    return null;
  }
  return text;
}
