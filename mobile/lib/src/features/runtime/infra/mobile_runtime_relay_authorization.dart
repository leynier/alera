part of 'mobile_runtime_client.dart';

const relayControlProtocol = 'alera-relay-control-v1';
const relayRenewalCapability = 'relayAuthorizationRenewalV1';

extension MobileRuntimeRelayAuthorization on MobileRuntimeClient {
  void _startRelayRenewal() {
    if (_requestRelayGrant == null ||
        _channel.protocol != relayControlProtocol ||
        !_runtimeCapabilities.contains(relayRenewalCapability)) {
      return;
    }
    final expiry = _grantExpiry(_relayGrant!);
    final remaining = expiry.difference(DateTime.now().toUtc());
    _relayExpiryTimer?.cancel();
    _relayExpiryTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () {
        if (isConnectionUsable) {
          _handleSocketError(const RuntimeConnectionLost());
        }
      },
    );
    final delay = remaining - const Duration(seconds: 30);
    _relayRenewalTimer?.cancel();
    _relayRenewalTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(_renewRelayAuthorization()),
    );
  }

  Future<void> _renewRelayAuthorization() async {
    if (!isConnectionUsable || _renewalAttempt != null) return;
    final attempt = ConnectionAttempt(timeout: const Duration(seconds: 25));
    _renewalAttempt = attempt;
    try {
      await attempt.run(() async {
        final previous = _relayGrant!;
        final renewed = await _requestRelayGrant!();
        attempt.check();
        if (!isConnectionUsable) return;
        if (renewed.accountId != previous.accountId ||
            renewed.runtimeId != previous.runtimeId ||
            renewed.clientId != previous.clientId ||
            renewed.clientKind != previous.clientKind ||
            renewed.clientKeyVersion != previous.clientKeyVersion ||
            renewed.clientPublicKey != previous.clientPublicKey ||
            renewed.runtimePublicKey != previous.runtimePublicKey ||
            !_grantExpiry(renewed).isAfter(_grantExpiry(previous))) {
          throw const RelayCryptoException('Relay renewal changed identity.');
        }
        final runtime = await requestMap('mobile.relayAuthorization.renew', {
          'grant': renewed.grant,
        }, const Duration(seconds: 10));
        attempt.check();
        final expiry = _grantExpiry(renewed).millisecondsSinceEpoch ~/ 1000;
        if (runtime['expiresAt'] != expiry) {
          throw const FormatException('Invalid runtime renewal response.');
        }
        final reply = Completer<Map<String, Object?>>();
        _relayAuthorizationReply = reply;
        final id = ++_relayAuthorizationId;
        _channel.sink.add(<int>[
          0,
          0,
          ...utf8.encode(
            jsonEncode({
              'type': 'auth.renew',
              'id': id,
              'grant': renewed.grant,
            }),
          ),
        ]);
        final response = await reply.future.timeout(
          const Duration(seconds: 10),
        );
        attempt.check();
        if (response['code'] == 'relay_authorization_unavailable') {
          throw const AleraCloudException(
            'Relay authorization is temporarily unavailable.',
            statusCode: 503,
          );
        }
        if (response['type'] != 'auth.renewed' ||
            response['expiresAt'] != expiry) {
          throw const FormatException('Relay renewal was rejected.');
        }
        _relayGrant = renewed;
        _startRelayRenewal();
      });
    } on Object catch (error, stackTrace) {
      if (!isConnectionUsable) return;
      if (error is RelayCryptoException ||
          error is FormatException ||
          error is StateError ||
          (error is AleraCloudException &&
              (error.statusCode == 401 || error.statusCode == 403))) {
        _handleSocketError(error, stackTrace);
      } else {
        // The old authorization remains valid only until its original deadline.
        _relayRenewalTimer = Timer(
          const Duration(seconds: 2),
          () => unawaited(_renewRelayAuthorization()),
        );
      }
    } finally {
      attempt.cancel();
      if (identical(_renewalAttempt, attempt)) _renewalAttempt = null;
      _relayAuthorizationReply = null;
    }
  }

  bool _handleRelayControl(Object? raw) {
    if (raw is! List<int> || raw.length < 2 || raw[0] != 0 || raw[1] != 0) {
      return false;
    }
    try {
      if (_channel.protocol != relayControlProtocol || raw.length > 16384) {
        throw const FormatException('Invalid relay control.');
      }
      final value = asJsonMap(jsonDecode(utf8.decode(raw.sublist(2))));
      final reply = _relayAuthorizationReply;
      if (value['id'] == _relayAuthorizationId &&
          reply != null &&
          !reply.isCompleted) {
        reply.complete(value);
      }
    } on Object catch (error, stackTrace) {
      _handleSocketError(error, stackTrace);
    }
    return true;
  }

  void _stopRelayRenewal() {
    _relayRenewalTimer?.cancel();
    _relayExpiryTimer?.cancel();
    _renewalAttempt?.cancel();
  }
}

DateTime _grantExpiry(CloudRelayGrant grant) {
  final parts = grant.grant.split('.');
  if (parts.length != 3) throw const FormatException('Invalid relay grant.');
  final claims = asJsonMap(
    jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))),
  );
  final expiry = claims['exp'];
  if (expiry is! int) {
    throw const FormatException('Missing relay grant expiry.');
  }
  return DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true);
}
