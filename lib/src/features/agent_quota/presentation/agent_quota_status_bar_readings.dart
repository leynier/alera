part of 'agent_quota_status_bar.dart';

class _QuotaReading {
  const _QuotaReading({
    required this.label,
    required this.remainingPercent,
    required this.order,
  });

  final String label;
  final double remainingPercent;
  final int order;
}

class _QuotaReadingView extends StatelessWidget {
  const _QuotaReadingView({
    required this.reading,
    required this.status,
    required this.compact,
  });

  final _QuotaReading reading;
  final AgentQuotaStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          reading.label,
          style: AleraTokens.monoStyle.copyWith(
            fontSize: compact ? 8 : 9,
            fontWeight: FontWeight.w500,
            color: AleraTokens.foregroundFaint,
          ),
        ),
        const SizedBox(width: AleraTokens.space2),
        Text(
          '${reading.remainingPercent.round()}%',
          style: AleraTokens.monoStyle.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _quotaColor(status, reading.remainingPercent),
          ),
        ),
      ],
    );
  }
}

List<_QuotaReading> _quotaReadings(AgentQuotaSnapshot snapshot) {
  final readings = <_QuotaReading>[
    for (final window in snapshot.windows)
      _QuotaReading(
        label: _windowReadingLabel(snapshot.provider, window.label),
        remainingPercent: window.remainingPercent,
        order: _readingOrder(snapshot.provider, window.label),
      ),
    for (final bucket in snapshot.buckets)
      _QuotaReading(
        label: _bucketReadingLabel(snapshot.provider, bucket),
        remainingPercent: bucket.remainingPercent,
        order: _readingOrder(snapshot.provider, bucket.name),
      ),
  ];
  readings.sort((left, right) => left.order.compareTo(right.order));
  return readings;
}

String _windowReadingLabel(AgentQuotaProviderId provider, String label) {
  if (provider == AgentQuotaProviderId.claude &&
      label.toLowerCase().contains('fable')) {
    return 'F';
  }
  return _shortWindowLabel(label);
}

String _bucketReadingLabel(
  AgentQuotaProviderId provider,
  AgentQuotaBucket bucket,
) {
  final lower = bucket.name.toLowerCase();
  if (provider == AgentQuotaProviderId.claude && lower.contains('fable')) {
    return 'F';
  }
  if (provider == AgentQuotaProviderId.antigravity) {
    final group = lower.contains('gemini') ? 'G' : 'C/G';
    return '$group·${_shortWindowLabel(bucket.name)}';
  }
  if (provider == AgentQuotaProviderId.zai) {
    return lower.contains('mcp') ? 'MCP' : _shortWindowLabel(bucket.name);
  }
  if (provider == AgentQuotaProviderId.minimax) {
    final model = bucket.name
        .replaceFirst(RegExp(r'\s+Weekly$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^MiniMax-', caseSensitive: false), '');
    final compactModel = switch (model.trim().toLowerCase()) {
      'general' => 'G',
      'video' => 'V',
      _ => _compactModelLabel(model),
    };
    return '$compactModel·${_shortWindowLabel(bucket.name)}';
  }
  return _shortWindowLabel(bucket.name);
}

String _shortWindowLabel(String label) {
  final lower = label.toLowerCase();
  if (lower.contains('5 hour') || lower.contains('5h')) {
    return '5H';
  }
  if (lower.contains('weekly') || lower.contains('week')) {
    return 'W';
  }
  if (lower.contains('month')) {
    return 'M';
  }
  if (lower.contains('day')) {
    return 'D';
  }
  return label.length <= 4 ? label.toUpperCase() : 'Q';
}

String _compactModelLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 6) {
    return trimmed;
  }
  final version = RegExp(
    r'M\d+(?:\.\d+)*',
    caseSensitive: false,
  ).firstMatch(trimmed)?.group(0);
  return version ?? trimmed.substring(0, 6);
}

int _readingOrder(AgentQuotaProviderId provider, String label) {
  final lower = label.toLowerCase();
  if (provider == AgentQuotaProviderId.claude) {
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
  if (provider == AgentQuotaProviderId.antigravity) {
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
