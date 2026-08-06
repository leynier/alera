import 'package:alera_mobile/src/features/quotas/domain/quota_settings.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_snapshot.dart';

/// Snapshots in provider settings order, with Claude Default/profiles ordered.
List<QuotaSnapshot> sortedQuotaSnapshots(
  Iterable<QuotaSnapshot> snapshots, {
  QuotaSettings? settings,
}) {
  final order = settings?.enabledProviders ?? supportedQuotaProviders;
  final byProvider = <String, List<QuotaSnapshot>>{};
  for (final snapshot in snapshots) {
    byProvider
        .putIfAbsent(snapshot.provider, () => <QuotaSnapshot>[])
        .add(snapshot);
  }

  final visible = <QuotaSnapshot>[];
  for (final provider in order) {
    final candidates = byProvider.remove(provider);
    if (candidates == null || candidates.isEmpty) {
      continue;
    }
    if (provider == 'claude') {
      visible.addAll(_orderedClaudeSnapshots(candidates, settings));
    } else {
      candidates.sort(
        (left, right) => left.displayName.compareTo(right.displayName),
      );
      visible.addAll(candidates);
    }
  }

  // Keep any unexpected providers after the configured order.
  final remaining = byProvider.values.expand((items) => items).toList()
    ..sort((left, right) {
      final byProviderName = left.provider.compareTo(right.provider);
      return byProviderName != 0
          ? byProviderName
          : left.displayName.compareTo(right.displayName);
    });
  visible.addAll(remaining);
  return visible;
}

List<QuotaSnapshot> _orderedClaudeSnapshots(
  List<QuotaSnapshot> candidates,
  QuotaSettings? settings,
) {
  final byAccount = <String, QuotaSnapshot>{
    for (final snapshot in candidates) snapshot.accountId: snapshot,
  };
  final ordered = <QuotaSnapshot>[];
  final added = <String>{};

  final defaultEnabled = settings?.claudeDefaultEnabled ?? true;
  if (defaultEnabled) {
    final defaultSnapshot = byAccount['default'];
    if (defaultSnapshot != null) {
      ordered.add(defaultSnapshot);
      added.add('default');
    }
  } else {
    added.add('default');
  }

  for (final profile
      in settings?.claudeProfiles ?? const <ClaudeQuotaProfile>[]) {
    final snapshot = byAccount[profile.profile];
    if (snapshot != null) {
      ordered.add(snapshot);
      added.add(profile.profile);
    }
  }

  final leftovers =
      candidates
          .where((snapshot) => !added.contains(snapshot.accountId))
          .toList()
        ..sort((left, right) => left.displayName.compareTo(right.displayName));
  ordered.addAll(leftovers);
  return ordered;
}

/// Windows then buckets, sorted by the desktop reading order.
List<QuotaMeter> sortedQuotaMeters(QuotaSnapshot snapshot) {
  final meters = <QuotaMeter>[...snapshot.windows, ...snapshot.buckets]
    ..addAll(
      snapshot.amounts.map(
        (amount) => QuotaMeter(
          label: amount.label,
          usedPercent: 0,
          resetsAt: amount.resetsAt,
          resetDescription: amount.resetDescription,
          displayValue: _amountDisplay(amount),
        ),
      ),
    )
    ..sort(
      (left, right) => quotaMeterReadingOrder(
        snapshot.provider,
        left.label,
      ).compareTo(quotaMeterReadingOrder(snapshot.provider, right.label)),
    );
  return meters;
}

String _amountDisplay(QuotaAmount amount) {
  final value = amount.spentAmount ?? amount.remainingAmount ?? amount.limitAmount;
  return value == null ? 'n/a' : '${amount.currency} ${value.toStringAsFixed(2)}';
}

int quotaMeterReadingOrder(String provider, String label) {
  final lower = label.toLowerCase();
  if (provider == 'claude') {
    if (lower.contains('5 hour') || lower.contains('5h')) {
      return 0;
    }
    if (lower.contains('fable')) {
      return 2;
    }
    if (lower.contains('week')) {
      return 1;
    }
  }
  if (provider == 'antigravity') {
    final group = lower.contains('gemini') ? 0 : 10;
    final window = lower.contains('5 hour') || lower.contains('5h') ? 0 : 1;
    return group + window;
  }
  if (lower.contains('5 hour') || lower.contains('5h')) {
    return 0;
  }
  if (lower.contains('week')) {
    return 1;
  }
  if (lower.contains('month')) {
    return 2;
  }
  return 3;
}
