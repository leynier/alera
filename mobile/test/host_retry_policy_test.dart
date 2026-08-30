import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/host_reachability.dart';
import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:alera_mobile/src/features/runtime/domain/host_retry_policy.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Only transport failures and transient HTTP statuses retry', () {
    expect(isRetryableHostFailure(TimeoutException('timeout')), isTrue);
    for (final status in [408, 429, 500, 503]) {
      expect(
        isRetryableHostFailure(
          AleraCloudException('cloud', statusCode: status),
        ),
        isTrue,
      );
    }
    for (final status in [400, 401, 403, 404, 409]) {
      expect(
        isRetryableHostFailure(
          AleraCloudException('cloud', statusCode: status),
        ),
        isFalse,
      );
    }
    expect(
      isRetryableHostFailure(const RelayCryptoException('replay')),
      isFalse,
    );
    expect(isRetryableHostFailure(const FormatException('version')), isFalse);
    expect(isRetryableHostFailure(StateError('revoked')), isFalse);
    expect(isRetryableHostFailure(const RuntimeConnectionReplaced()), isFalse);
    expect(
      hostFailureCause(const RuntimeConnectionReplaced()),
      'connection_replaced',
    );
  });

  test('Backoff is bounded, randomized, capped and honors Retry-After', () {
    final error = TimeoutException('timeout');
    for (var attempt = 0; attempt < 8; attempt++) {
      final cap = [1, 2, 4, 8, 16, 30, 30, 30][attempt] * 1000;
      final samples = List.generate(
        20,
        (_) => hostRetryDelay(attempt, error).inMilliseconds,
      );
      expect(
        samples.every((value) => value >= cap ~/ 2 && value <= cap),
        isTrue,
      );
      expect(samples.toSet().length, greaterThan(1));
    }
    const busy = AleraCloudException(
      'busy',
      statusCode: 429,
      retryAfter: Duration(seconds: 90),
    );
    expect(
      hostRetryDelay(0, busy, immediate: true),
      const Duration(seconds: 90),
    );
    expect(hostRetryDelay(0, error, immediate: true), Duration.zero);
  });
}
