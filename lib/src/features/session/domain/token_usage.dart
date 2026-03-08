/// Token usage breakdown from a single LLM request or accumulated session.
class TokenUsage {
  const TokenUsage({
    this.inputTokens = 0,
    this.cachedInputTokens = 0,
    this.outputTokens = 0,
    this.reasoningOutputTokens = 0,
    this.totalTokens = 0,
  });

  final int inputTokens;
  final int cachedInputTokens;
  final int outputTokens;
  final int reasoningOutputTokens;
  final int totalTokens;

  int get nonCachedInputTokens {
    final value = inputTokens - cachedInputTokens;
    return value > 0 ? value : 0;
  }

  int get blendedTotalTokens =>
      nonCachedInputTokens + (outputTokens < 0 ? 0 : outputTokens);

  factory TokenUsage.fromMap(Map<String, dynamic> map) {
    return TokenUsage(
      inputTokens:
          _intOr(map['input_tokens']) ?? _intOr(map['inputTokens']) ?? 0,
      cachedInputTokens:
          _intOr(map['cached_input_tokens']) ??
          _intOr(map['cachedInputTokens']) ??
          0,
      outputTokens:
          _intOr(map['output_tokens']) ?? _intOr(map['outputTokens']) ?? 0,
      reasoningOutputTokens:
          _intOr(map['reasoning_output_tokens']) ??
          _intOr(map['reasoningOutputTokens']) ??
          0,
      totalTokens:
          _intOr(map['total_tokens']) ?? _intOr(map['totalTokens']) ?? 0,
    );
  }

  static const empty = TokenUsage();
}

/// Aggregated token usage info including context window size.
class TokenUsageInfo {
  const TokenUsageInfo({
    this.totalTokenUsage = TokenUsage.empty,
    this.lastTokenUsage = TokenUsage.empty,
    this.modelContextWindow,
  });

  /// Accumulated token usage across the entire session.
  final TokenUsage totalTokenUsage;

  /// Token usage from the most recent LLM request.
  final TokenUsage lastTokenUsage;

  /// Maximum context window size for the active model (in tokens).
  final int? modelContextWindow;

  /// Tokens occupying the current context window.
  ///
  /// Prefer the last turn usage when present because `totalTokenUsage` is
  /// cumulative across the session and can otherwise overstate current context.
  int get currentContextTokens {
    final last = lastTokenUsage.totalTokens;
    if (last > 0) {
      return last;
    }
    return totalTokenUsage.totalTokens;
  }

  /// Blended session usage for display as an accumulated "tokens used" value.
  int get blendedTotalTokens => totalTokenUsage.blendedTotalTokens;

  /// Percentage of the context window remaining (0–100).
  /// Returns `null` if the context window is unknown.
  double? get percentRemaining {
    final window = modelContextWindow;
    if (window == null || window <= 0) return null;
    final used = currentContextTokens;
    final pct = 100.0 - (used / window * 100.0);
    return pct.clamp(0.0, 100.0);
  }

  factory TokenUsageInfo.fromMap(Map<String, dynamic> map) {
    final totalMap =
        _mapOr(map['total_token_usage']) ??
        _mapOr(map['totalTokenUsage']) ??
        const <String, dynamic>{};
    final lastMap =
        _mapOr(map['last_token_usage']) ??
        _mapOr(map['lastTokenUsage']) ??
        const <String, dynamic>{};
    final window =
        _intOr(map['model_context_window']) ??
        _intOr(map['modelContextWindow']);
    return TokenUsageInfo(
      totalTokenUsage: totalMap.isEmpty
          ? TokenUsage.empty
          : TokenUsage.fromMap(totalMap),
      lastTokenUsage: lastMap.isEmpty
          ? TokenUsage.empty
          : TokenUsage.fromMap(lastMap),
      modelContextWindow: window,
    );
  }

  static const empty = TokenUsageInfo();
}

/// Rate limit window snapshot.
class RateLimitWindow {
  const RateLimitWindow({
    this.usedPercent = 0.0,
    this.windowDurationMins,
    this.resetsAt,
  });

  final double usedPercent;
  final int? windowDurationMins;
  final int? resetsAt;

  factory RateLimitWindow.fromMap(Map<String, dynamic> map) {
    return RateLimitWindow(
      usedPercent:
          _doubleOr(map['used_percent']) ??
          _doubleOr(map['usedPercent']) ??
          0.0,
      windowDurationMins:
          _intOr(map['window_minutes']) ??
          _intOr(map['windowMinutes']) ??
          _intOr(map['window_duration_mins']) ??
          _intOr(map['windowDurationMins']),
      resetsAt: _intOr(map['resets_at']) ?? _intOr(map['resetsAt']),
    );
  }
}

/// Credits information from the API.
class CreditsSnapshot {
  const CreditsSnapshot({
    this.hasCredits = false,
    this.unlimited = false,
    this.balance,
  });

  final bool hasCredits;
  final bool unlimited;
  final String? balance;

  factory CreditsSnapshot.fromMap(Map<String, dynamic> map) {
    return CreditsSnapshot(
      hasCredits:
          map['has_credits'] as bool? ?? map['hasCredits'] as bool? ?? false,
      unlimited: map['unlimited'] as bool? ?? false,
      balance: map['balance'] as String?,
    );
  }
}

/// Combined rate limit + credits snapshot.
class RateLimitSnapshot {
  const RateLimitSnapshot({
    this.primary,
    this.secondary,
    this.credits,
    this.planType,
  });

  final RateLimitWindow? primary;
  final RateLimitWindow? secondary;
  final CreditsSnapshot? credits;
  final String? planType;

  factory RateLimitSnapshot.fromMap(Map<String, dynamic> map) {
    final primaryMap = _mapOr(map['primary']);
    final secondaryMap = _mapOr(map['secondary']);
    final creditsMap = _mapOr(map['credits']);
    return RateLimitSnapshot(
      primary: primaryMap != null ? RateLimitWindow.fromMap(primaryMap) : null,
      secondary: secondaryMap != null
          ? RateLimitWindow.fromMap(secondaryMap)
          : null,
      credits: creditsMap != null ? CreditsSnapshot.fromMap(creditsMap) : null,
      planType: map['plan_type'] as String? ?? map['planType'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

int? _intOr(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

double? _doubleOr(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return null;
}

Map<String, dynamic>? _mapOr(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}
