part of 'agent_usage_dialog.dart';

String _formatUsageTokens(int value) {
  if (value >= 1000000000000) {
    return '${_trimUsageNumber(value / 1000000000000)}T';
  }
  if (value >= 1000000000) return '${_trimUsageNumber(value / 1000000000)}B';
  if (value >= 1000000) return '${_trimUsageNumber(value / 1000000)}M';
  if (value >= 1000) return '${_trimUsageNumber(value / 1000)}K';
  return value.toString();
}

String _trimUsageNumber(double value) {
  final digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return value.toStringAsFixed(digits).replaceFirst(RegExp(r'\.0+$'), '');
}

String _formatUsageUsd(double value) => '\$${value.toStringAsFixed(2)}';

String _formatUsagePercent(double share) =>
    '${(share * 100).toStringAsFixed(1)}% of input';

String _formatUsageCount(int value) {
  final raw = value.toString();
  final output = StringBuffer();
  for (var index = 0; index < raw.length; index++) {
    if (index > 0 && (raw.length - index) % 3 == 0) output.write(',');
    output.write(raw[index]);
  }
  return output.toString();
}

String _formatUsageDay(String value) {
  final parts = value.split('-');
  if (parts.length != 3) return value;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (month == null || day == null || month < 1 || month > 12) return value;
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[month - 1]} $day';
}

String _usageProviderLabel(AgentUsageProvider provider) => switch (provider) {
  AgentUsageProvider.claude => 'Claude Code',
  AgentUsageProvider.codex => 'Codex',
};

String _usagePricingDetail(AgentUsageSnapshot snapshot) {
  final unpriced = snapshot.buckets.fold(
    0,
    (sum, bucket) => sum + bucket.unpricedRecords,
  );
  if (unpriced > 0) return '$unpriced unpriced responses';
  return switch (snapshot.pricing.status) {
    AgentUsagePricingStatus.fresh => 'Current model rates',
    AgentUsagePricingStatus.cached => 'Cached model rates',
    AgentUsagePricingStatus.unavailable => 'Pricing unavailable',
  };
}
