// Formatting utilities for the app.

/// Formats a token count for display.
/// Uses K for thousands, M for millions with smart decimal handling.
/// Examples: 1500 -> 1.5K, 1000 -> 1K, 1500000 -> 1.5M
String formatTokenCount(int count) {
  if (count >= 1000000) {
    final m = count / 1000000;
    return '${m.toStringAsFixed(m.truncateToDouble() == m ? 0 : 1)}M';
  }
  if (count >= 1000) {
    final k = count / 1000;
    return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}K';
  }
  return count.toString();
}
