import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:alera_mobile/src/features/runtime/domain/host_reachability.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_crypto.dart';

const _seconds = [1, 2, 4, 8, 16, 30];

bool isRetryableHostFailure(Object error) {
  if (error is http.ClientException) {
    final message = error.message.toLowerCase();
    return !message.contains('certificate') && !message.contains('handshake');
  }
  if (error is AleraCloudException) {
    return error.statusCode == 408 ||
        error.statusCode == 429 ||
        (error.statusCode ?? 0) >= 500;
  }
  if (error is StateError ||
      error is FormatException ||
      error is RelayCryptoException) {
    return false;
  }
  return isHostReachabilityFailure(normalizeHostConnectionError(error));
}

String hostFailureCause(Object error) {
  if (error is RuntimeConnectionReplaced) return 'connection_replaced';
  if (error is RelayCryptoException) return 'cryptographic_failure';
  if (error is AleraCloudException) {
    return isRetryableHostFailure(error)
        ? 'cloud_unavailable'
        : 'authorization_failed';
  }
  if (error is StateError || error is FormatException) {
    return 'protocol_incompatible';
  }
  return 'transport_unavailable';
}

Duration hostRetryDelay(int attempt, Object error, {bool immediate = false}) {
  final milliseconds = _seconds[attempt.clamp(0, _seconds.length - 1)] * 1000;
  var delay = immediate && attempt == 0
      ? Duration.zero
      : Duration(
          milliseconds:
              milliseconds ~/ 2 + Random().nextInt(milliseconds ~/ 2 + 1),
        );
  if (error is AleraCloudException &&
      error.retryAfter != null &&
      error.retryAfter! > delay) {
    delay = error.retryAfter!;
  }
  return delay;
}
