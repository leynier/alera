import 'package:alera/src/features/session/domain/token_usage.dart';

/// Aggregated context usage state for a session.
///
/// Updated on each `thread/tokenUsage/updated` event.
class ContextUsage {
  const ContextUsage({
    this.tokenUsageInfo = TokenUsageInfo.empty,
    this.rateLimits,
    this.isCompacting = false,
  });

  /// Latest token usage info including context window size.
  final TokenUsageInfo tokenUsageInfo;

  /// Latest rate limit snapshot (may be null if not provided).
  final RateLimitSnapshot? rateLimits;

  /// Whether a context compaction is currently in progress.
  final bool isCompacting;

  /// Total tokens currently in context.
  int get tokensInContext => tokenUsageInfo.currentContextTokens;

  /// Accumulated blended session usage.
  int get sessionTokensUsed => tokenUsageInfo.blendedTotalTokens;

  /// Maximum context window size, or null if unknown.
  int? get contextWindowSize => tokenUsageInfo.modelContextWindow;

  /// Percentage of context remaining (0–100), or null if unknown.
  double? get percentRemaining => tokenUsageInfo.percentRemaining;

  ContextUsage copyWith({
    TokenUsageInfo? tokenUsageInfo,
    RateLimitSnapshot? rateLimits,
    bool clearRateLimits = false,
    bool? isCompacting,
  }) {
    return ContextUsage(
      tokenUsageInfo: tokenUsageInfo ?? this.tokenUsageInfo,
      rateLimits: clearRateLimits ? null : (rateLimits ?? this.rateLimits),
      isCompacting: isCompacting ?? this.isCompacting,
    );
  }

  static const empty = ContextUsage();
}
