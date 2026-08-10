import 'package:alera/src/rust/api/reading_diff.dart' as rust;

String buildReadingDiffPrompt({
  required rust.ReadingDiffPreparation preparation,
  required rust.ReadingDiffChunk chunk,
  required String customInstructions,
}) {
  return '''
You are preparing a non-applicable reading diff. Return only one JSON object matching the supplied schema.

Contract: MeatPlanV${preparation.schemaVersion}
Rubric: ${preparation.rubricVersion}

The original numbered unified diff below is immutable. Line numbers before `|` are coordinates, not source text. You may only propose:
- remove: inclusive ranges of hunk source rows that are review noise;
- replace: one exact source span with a strict source projection that only removes text and inserts `...` or `…`;
- fold: inclusive ranges of at least two rows within one hunk and one diff marker;
- summary: one concise sentence describing the behavioral change.

Never remove or alter file headers, hunk headers, rename/copy metadata, mode metadata, binary markers, no-newline markers, or format-patch trailers. Keep moved code symmetric. Keep Python decorators, suite owners, delimiter boundaries, and definitions needed by retained rows. Imports are elided deterministically by Alera and do not need plan entries. Prefer retaining uncertain lines. The Rust compiler rejects invented text and is the final authority.

<user_instructions>
${customInstructions.trim().isEmpty ? '(none)' : customInstructions.trim()}
</user_instructions>

<numbered_diff chunk="${chunk.index + 1}" total="${preparation.chunks.length}">
${chunk.numberedDiff}
</numbered_diff>
'''
      .trim();
}

String buildReadingDiffRepairPrompt({
  required String originalPrompt,
  required String rejectedPlan,
  required String compilerError,
}) {
  return '''
$originalPrompt

Your previous complete plan was rejected by the deterministic compiler:
<compiler_error>
$compilerError
</compiler_error>

<rejected_plan>
$rejectedPlan
</rejected_plan>

Return a complete replacement plan against the original numbered coordinates. Do not return a patch or commentary.
'''
      .trim();
}
