import 'package:alera_mobile/src/features/quotas/presentation/quota_display_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strips MiniMax provider suffix from meter labels', () {
    expect(quotaMeterDisplayLabel('minimax', 'General en MiniMax'), 'General');
    expect(
      quotaMeterDisplayLabel('minimax', 'general Weekly'),
      'General Weekly',
    );
    expect(
      quotaMeterDisplayLabel('minimax', 'MiniMax-General Weekly'),
      'General Weekly',
    );
  });

  test('keeps non-MiniMax labels normalized without forced capitalization', () {
    expect(quotaMeterDisplayLabel('claude', '5 Hour'), '5 Hour');
    expect(normalizeQuotaText('Gpt-4 – Plan'), 'GPT-4 - Plan');
  });
  test('builds Claude titles with Default or CCS profile', () {
    expect(
      quotaSnapshotTitle(
        provider: 'claude',
        accountId: 'default',
        displayName: 'Default',
      ),
      'Claude Code - Default',
    );
    expect(
      quotaSnapshotTitle(
        provider: 'claude',
        accountId: 'partsbase',
        displayName: 'Partsbase',
      ),
      'Claude Code - Partsbase',
    );
    expect(
      quotaSnapshotTitle(
        provider: 'minimax',
        accountId: 'default',
        displayName: 'MiniMax',
      ),
      'MiniMax',
    );
  });
}
