import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';

const int stagedDiffPromptBudget = 200000;

class const AiAssistCommitContext({
  required final String? branch,
  required final String stagedSummary,
  required final String stagedPatch,
});

class const AiAssistPullRequestContext({
  required final String baseBranch,
  required final String? headBranch,
  required final String commitSummary,
  required final String fileSummary,
  required final String patch,
});

class const GeneratedPullRequestDetails({
  required final String title,
  final String? body,
});

String buildCommitMessagePrompt({
  required AiAssistCommitContext context,
  required String customInstructions,
}) {
  final base = <String>[
    'You are generating a single git commit message.',
    'Return only the commit message text. Do not include a preamble, quotes, or code fences.',
    '',
    'Rules:',
    '- First line: imperative mood, <= 72 chars, no trailing period.',
    '- Optional body: blank line, then short wrapped bullet points or prose explaining WHY.',
    '- Capture the primary user-visible or developer-visible change.',
    '- Use only the staged changes below as context.',
    '- Do not include "Co-authored-by" or other git trailers.',
    '',
    'Branch: ${context.branch ?? '(detached)'}',
    '',
    'Staged files:',
    limitPromptSection(context.stagedSummary, 6000),
    '',
    'Staged patch:',
    '```diff',
    truncateDiffForPrompt(context.stagedPatch),
    '```',
  ].join('\n');

  return _withCustomInstructions(base, customInstructions);
}

String buildPullRequestDetailsPrompt({
  required AiAssistPullRequestContext context,
  required String customInstructions,
}) {
  final base = <String>[
    'You are generating a GitHub-style pull request title and description.',
    'Return only the PR text. Do not include a preamble, quotes, or code fences.',
    '',
    'Rules:',
    '- First line: concise PR title (imperative mood preferred, <= 72 chars, no trailing period).',
    '- Then a blank line.',
    '- Then a markdown-friendly description explaining WHAT changed and WHY.',
    '- Use only the commits and patch range below as context.',
    '- Do not invent reviewers, issue numbers, or screenshots that are not in the context.',
    '',
    'Base branch: ${context.baseBranch}',
    'Head branch: ${context.headBranch ?? '(detached)'}',
    '',
    'Commits (newest first):',
    limitPromptSection(context.commitSummary, 8000),
    '',
    'Changed files:',
    limitPromptSection(context.fileSummary, 6000),
    '',
    'Patch range:',
    '```diff',
    truncateDiffForPrompt(context.patch),
    '```',
  ].join('\n');

  return _withCustomInstructions(base, customInstructions);
}

String _withCustomInstructions(String base, String customInstructions) {
  final trimmed = customInstructions.trim();
  if (trimmed.isEmpty) {
    return base;
  }
  return <String>[
    base,
    '',
    'Additional user instructions:',
    limitPromptSection(trimmed, 4000),
  ].join('\n');
}

GeneratedPullRequestDetails parseGeneratedPullRequestDetails(String raw) {
  final normalized = cleanGeneratedText(raw);
  final lines = normalized.split('\n');
  final subject = (lines.isEmpty ? '' : lines.first).trim().replaceFirst(
    RegExp(r'[.]+$'),
    '',
  );
  final title = subject.isEmpty
      ? 'Update Project'
      : subject
            .substring(0, subject.length > 72 ? 72 : subject.length)
            .trimRight();
  final body = lines.skip(1).join('\n').trim();
  return GeneratedPullRequestDetails(
    title: title,
    body: body.isEmpty ? null : body,
  );
}

String limitPromptSection(String value, int maxChars) {
  if (value.length <= maxChars) {
    return value;
  }
  final omitted = value.length - maxChars;
  return '${value.substring(0, maxChars)}\n\n[truncated: $omitted characters omitted]';
}

String truncateDiffForPrompt(
  String diff, {
  int budget = stagedDiffPromptBudget,
}) {
  if (diff.length <= budget) {
    return diff;
  }
  final omitted = diff.length - budget;
  return '${diff.substring(0, budget)}\n...(diff truncated, $omitted characters omitted)';
}

String cleanGeneratedText(String raw) {
  var text = raw.replaceAll('\r\n', '\n').trim();
  final firstNewline = text.indexOf('\n');
  if (firstNewline != -1) {
    final firstLine = text.substring(0, firstNewline).trim();
    if (RegExp(
          r'^(generating|thinking)\b',
          caseSensitive: false,
        ).hasMatch(firstLine) ||
        RegExp(r'^[.…]+$').hasMatch(firstLine)) {
      text = text.substring(firstNewline + 1).trim();
    }
  }
  final fenced = RegExp(r'^```[a-zA-Z0-9_-]*\n([\s\S]*?)\n```$')
      .firstMatch(text);
  if (fenced != null) {
    text = fenced.group(1)!.trim();
  }
  return text;
}

String cleanGeneratedCommitMessage(String raw) {
  final normalized = cleanGeneratedText(raw);
  final lines = normalized.split('\n');
  final subject = (lines.isEmpty ? '' : lines.first).trim().replaceFirst(
    RegExp(r'[.]+$'),
    '',
  );
  final candidate = subject.isEmpty ? 'Update project files' : subject;
  final safeSubject = candidate
      .substring(0, candidate.length > 72 ? 72 : candidate.length)
      .trimRight();
  final body = lines.skip(1).join('\n').trim();
  return body.isEmpty ? safeSubject : '$safeSubject\n\n$body';
}

String promptInstructionsFor(
  AiAssistSettings settings,
  AiAssistOperation operation,
) {
  return settings.instructionsFor(operation);
}
