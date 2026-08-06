import 'package:alera_mobile/src/features/quotas/domain/quota_settings.dart';

/// Normalizes quota copy to match desktop hover/status presentation.
String normalizeQuotaText(String value) {
  return value.replaceAll('–', '-').replaceAll(RegExp(r'\bGpt\b'), 'GPT');
}

/// Meter / window label for quotas UI (Home summary and Quotas screen).
///
/// MiniMax often returns lowercase model names (`general Weekly`) or redundant
/// provider suffixes (`General en MiniMax`); strip the provider noise and match
/// desktop capitalization.
String quotaMeterDisplayLabel(String provider, String value) {
  final providerLabel = quotaProviderLabels[provider] ?? provider;
  var label = normalizeQuotaText(value).trim();
  if (label.isEmpty) {
    return label;
  }

  label = label
      .replaceFirst(
        RegExp(
          '^${RegExp.escape(providerLabel)}[-:\\s]+',
          caseSensitive: false,
        ),
        '',
      )
      .replaceFirst(
        RegExp('^${RegExp.escape(provider)}[-:\\s]+', caseSensitive: false),
        '',
      )
      .replaceFirst(
        RegExp(
          '\\s+(en|on|[-|@])\\s*${RegExp.escape(providerLabel)}\$',
          caseSensitive: false,
        ),
        '',
      )
      .replaceFirst(
        RegExp(
          '\\s+(en|on|[-|@])\\s*${RegExp.escape(provider)}\$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  if (provider == 'minimax' && label.isNotEmpty) {
    label = label[0].toUpperCase() + label.substring(1);
  }
  return label;
}

String quotaProviderDisplayLabel(String provider) {
  return quotaProviderLabels[provider] ?? provider;
}

/// Title for a quota snapshot card (Home and Quotas screen).
///
/// Claude always includes the profile: `Claude Code - Default` or
/// `Claude Code - {alias}`. Other providers use the plain provider label.
String quotaSnapshotTitle({
  required String provider,
  required String accountId,
  required String displayName,
}) {
  final providerLabel = quotaProviderDisplayLabel(provider);
  if (provider == 'opencode') {
    final account = accountId == 'go' ? 'Go' : 'Zen';
    return '$providerLabel - $account';
  }
  if (provider != 'claude') {
    return providerLabel;
  }
  final profile = accountId == 'default' || displayName.trim().isEmpty
      ? 'Default'
      : displayName.trim();
  return '$providerLabel - $profile';
}
