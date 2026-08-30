part of 'mobile_runtime_client.dart';

Future<MobileRuntimeClient> _connectDirectTransport(
  String endpoint, {
  Duration connectTimeout = _defaultRequestTimeout,
}) async {
  final client = MobileRuntimeClient._(
    IOWebSocketChannel.connect(
      Uri.parse(endpoint),
      connectTimeout: connectTimeout,
    ),
  );
  final attempt = ConnectionAttempt.current;
  if (attempt != null) {
    unawaited(attempt.cancelled.then((_) => client.dispose()));
  }
  try {
    await client._channel.ready.timeout(connectTimeout);
    return client;
  } on Object catch (error, stackTrace) {
    await client.dispose();
    // Convert only transport reachability at this boundary. Authentication
    // and protocol errors happen later and retain their original types.
    Error.throwWithStackTrace(normalizeHostConnectionError(error), stackTrace);
  }
}

Future<MobileRuntimeClient> _connectRelayTransport({
  required CloudRelayGrant grant,
  required RelayIdentityKeyPair identity,
  Future<CloudRelayGrant> Function()? requestGrant,
}) async {
  final channel = IOWebSocketChannel.connect(
    grant.relayUrl,
    headers: <String, dynamic>{'authorization': 'Bearer ${grant.grant}'},
    protocols:
        const bool.fromEnvironment(
          'ALERA_RELAY_RENEWAL_ENABLED',
          defaultValue: true,
        )
        ? [relayControlProtocol]
        : null,
    connectTimeout: const Duration(seconds: 20),
  );
  final client = MobileRuntimeClient._(channel);
  client._relayGrant = grant;
  client._requestRelayGrant = requestGrant;
  final attempt = ConnectionAttempt.current;
  if (attempt != null) {
    unawaited(attempt.cancelled.then((_) => client.dispose()));
  }
  try {
    await channel.ready.timeout(client._requestTimeout);
    await client._performRelayHandshake(grant, identity);
    return client;
  } on Object catch (error, stackTrace) {
    await client.dispose();
    Error.throwWithStackTrace(_relayUpgradeError(error), stackTrace);
  }
}

Future<PairedDeviceCredentials> _pairDirectDevice(
  PairingOffer offer, {
  String? deviceName,
}) async {
  final client = await MobileRuntimeClient.connect(offer.endpoint);
  try {
    final deviceNameOverride = deviceName?.trim();
    final requestPayload = <String, Object?>{
      'pairingId': offer.pairingId,
      'pairingSecret': offer.pairingSecret,
      if (deviceNameOverride != null && deviceNameOverride.isNotEmpty)
        'deviceName': deviceNameOverride,
    };
    final payload = await client.requestMap(
      'mobile.device.pair',
      requestPayload,
    );
    return PairedDeviceCredentials.fromJson(payload);
  } finally {
    await client.dispose();
  }
}

Object _relayUpgradeError(Object error) {
  final cause = error is WebSocketChannelException
      ? error.inner ?? error
      : error;
  // dart:io exposes an upgrade's HTTP status only in this exception message.
  final status = RegExp(
    r'http status code:\s*(\d{3})',
    caseSensitive: false,
  ).firstMatch(cause.toString());
  final code = int.tryParse(status?.group(1) ?? '');
  if (code != null && code >= 400 && code <= 599) {
    return AleraCloudException(
      'Relay WebSocket upgrade was rejected.',
      statusCode: code,
    );
  }
  return normalizeHostConnectionError(error);
}
