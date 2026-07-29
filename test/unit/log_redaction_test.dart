import 'package:alera/src/shared/infra/logging/log_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(resetRegisteredLogSecrets);
  tearDown(resetRegisteredLogSecrets);

  group('redactLogText', () {
    test('masks keyed secrets regardless of separator or quoting', () {
      final redacted = redactLogText(
        'connecting token=abc123def456 and "secret": "hunter2hunter"',
      );

      expect(redacted, isNot(contains('abc123def456')));
      expect(redacted, isNot(contains('hunter2hunter')));
      expect(redacted, contains(kRedactedPlaceholder));
    });

    test('masks bearer headers', () {
      final redacted = redactLogText(
        'sent Bearer eyJhbGciOiJIUzI1NiJ9.payload upstream',
      );

      expect(redacted, isNot(contains('eyJhbGciOiJIUzI1NiJ9.payload')));
      expect(redacted, contains('Bearer $kRedactedPlaceholder'));
    });

    test('masks a registered literal with no key beside it', () {
      registerLogSecret('s3cret-control-token-value');

      final redacted = redactLogText(
        'client presented s3cret-control-token-value while attaching',
      );

      expect(redacted, isNot(contains('s3cret-control-token-value')));
      expect(redacted, contains(kRedactedPlaceholder));
    });

    test('ignores registered values too short to be distinctive', () {
      registerLogSecret('abc');

      expect(redactLogText('abc def'), 'abc def');
    });

    test('leaves ordinary diagnostic text untouched', () {
      const message = 'failed to open workspace ws-17: database is locked';

      expect(redactLogText(message), message);
    });

    test('masks a device token reported by the mobile transport', () {
      final redacted = redactLogText(
        '{"deviceToken":"kQ8f2mZp01xTuv","deviceId":"phone-1"}',
      );

      expect(redacted, isNot(contains('kQ8f2mZp01xTuv')));
      expect(redacted, contains('phone-1'));
    });
  });
}
