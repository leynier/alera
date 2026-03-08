import 'package:alera/src/features/session/domain/context_usage.dart';
import 'package:alera/src/features/session/domain/token_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('token usage helpers', () {
    test('blended total uses non-cached input plus output', () {
      const usage = TokenUsage(
        inputTokens: 100,
        cachedInputTokens: 40,
        outputTokens: 20,
      );

      expect(usage.nonCachedInputTokens, 60);
      expect(usage.blendedTotalTokens, 80);
    });

    test('current context tokens prefer last usage when present', () {
      const info = TokenUsageInfo(
        totalTokenUsage: TokenUsage(totalTokens: 205000),
        lastTokenUsage: TokenUsage(totalTokens: 12000),
        modelContextWindow: 128000,
      );

      expect(info.currentContextTokens, 12000);
      expect(info.percentRemaining, closeTo(90.625, 0.0001));
    });

    test('context usage falls back to total when last usage is empty', () {
      const usage = ContextUsage(
        tokenUsageInfo: TokenUsageInfo(
          totalTokenUsage: TokenUsage(
            inputTokens: 120,
            cachedInputTokens: 20,
            outputTokens: 30,
            totalTokens: 64000,
          ),
          lastTokenUsage: TokenUsage(totalTokens: 0),
          modelContextWindow: 128000,
        ),
      );

      expect(usage.tokensInContext, 64000);
      expect(usage.sessionTokensUsed, 130);
    });
  });
}
