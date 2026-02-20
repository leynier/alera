import 'package:alera/src/features/worktree/application/branch_name_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BranchNameGenerator', () {
    test('uses AI-provided branch when available', () async {
      final generator = BranchNameGenerator(
        aiSuggestion: (firstPrompt, timeout) async => 'feature/mcp-ui',
      );

      final result = await generator.generate(
        firstPrompt: 'add mcp ui',
        now: DateTime.utc(2026, 2, 20, 10, 11, 12),
      );

      expect(result, 'alera/feature/mcp-ui');
    });

    test('falls back to deterministic slug+timestamp when AI fails', () async {
      final generator = BranchNameGenerator(
        aiSuggestion: (firstPrompt, timeout) async => throw StateError('boom'),
      );

      final result = await generator.generate(
        firstPrompt: 'Add Worktree support now!',
        now: DateTime.utc(2026, 2, 20, 10, 11, 12),
      );

      expect(result, 'alera/add-worktree-support-now-20260220-101112');
    });
  });
}
