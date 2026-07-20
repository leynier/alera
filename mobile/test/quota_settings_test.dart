import 'package:alera_mobile/src/features/quotas/domain/quota_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Defaults providers only when the field is absent', () {
    expect(
      QuotaSettings.fromJson(const <String, Object?>{}).enabledProviders,
      supportedQuotaProviders,
    );
    expect(
      QuotaSettings.fromJson(const <String, Object?>{
        'enabledProviders': <Object?>[],
      }).enabledProviders,
      isEmpty,
    );
  });

  test('Filters unsupported providers while preserving display order', () {
    final settings = QuotaSettings.fromJson(const <String, Object?>{
      'enabledProviders': <Object?>['codex', 'unknown', 'claude'],
    });

    expect(settings.enabledProviders, <String>['codex', 'claude']);
  });
}
