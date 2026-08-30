part of 'mobile_runtime_client.dart';

mixin MobileRuntimeClientRelay {
  RelayCryptoSession? _relaySession;
  String? _relayClientId;
  Completer<Map<String, Object?>>? _relayHandshake;
  Timer? _relayFragmentTimer;
  final RelayFragmentReassembler _relayFragments = RelayFragmentReassembler();

  WebSocketChannel get _channel;
  bool get isConnectionUsable;
  Duration get _requestTimeout;
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);
  void _applyRelayCapabilities(Map<String, Object?> payload);
  void _handleDecodedMessage(Object? raw);
  void _handleSocketError(Object error, [StackTrace? stackTrace]);

  Future<Map<String, Object?>> authenticateRelay({
    String? cloudDeviceId,
  }) async {
    final relayClientId = _relayClientId;
    if (_relaySession == null || relayClientId == null) {
      throw StateError('The relay transport is not connected.');
    }
    registerLogSecret(relayClientId);
    final payload = await requestMap('mobile.hello', <String, Object?>{
      'protocolVersion': aleraMobileProtocolVersion,
      'deviceId': relayClientId,
      'deviceToken': '',
      'relayClientId': relayClientId,
      'cloudDeviceId': ?cloudDeviceId,
      'binaryFrames': true,
      'supportedTabKinds': const <String>['codex'],
    });
    _applyRelayCapabilities(payload);
    return payload;
  }

  Future<void> _handleRelayHandshakeMessage(Object? raw) async {
    try {
      final bytes = _messageBytes(raw);
      final (clientId, payload) = unwrapRelayFrame(bytes);
      if (clientId != _relayClientId) {
        throw const FormatException(
          'Relay handshake client ID does not match.',
        );
      }
      _relayHandshake?.complete(decodeRelayJson(payload));
    } on Object catch (error, stackTrace) {
      final pending = _relayHandshake;
      if (pending != null && !pending.isCompleted) {
        pending.completeError(error, stackTrace);
      }
    }
  }

  Future<void> _handleRelayMessage(Object? raw) async {
    try {
      final bytes = _messageBytes(raw);
      final (clientId, payload) = unwrapRelayFrame(bytes);
      if (clientId != _relayClientId) {
        return;
      }
      final envelope = _relayFragments.accept(payload);
      if (envelope == null) {
        _relayFragmentTimer ??= Timer(const Duration(seconds: 10), () {
          _relayFragments.clear();
          _handleSocketError(TimeoutException('Relay fragments expired.'));
        });
        return;
      }
      _relayFragmentTimer?.cancel();
      _relayFragmentTimer = null;
      final clear = await _relaySession!.open(envelope);
      _handleDecodedMessage(clear);
    } on Object catch (error, stackTrace) {
      _handleSocketError(error, stackTrace);
    }
  }

  Future<void> _performRelayHandshake(
    CloudRelayGrant grant,
    RelayIdentityKeyPair identity,
  ) async {
    if (grant.clientKind != 'mobile' || grant.runtimePublicKey == null) {
      throw const FormatException('The relay grant is not a mobile grant.');
    }
    if (grant.expiresIn <= 0 ||
        grant.expiresIn > 120 ||
        grant.clientKeyVersion <= 0 ||
        grant.clientPublicKey != base64UrlNoPadding(identity.publicBytes)) {
      throw const FormatException('The relay grant identity is invalid.');
    }
    final random = Random.secure();
    final nonce = List<int>.generate(16, (_) => random.nextInt(256));
    final ephemeral = await RelayIdentityKeyPair.generate();
    _relayClientId = grant.clientId;
    final handshake = Completer<Map<String, Object?>>();
    _relayHandshake = handshake;
    if (!isConnectionUsable) throw const RuntimeConnectionLost();
    _channel.sink.add(
      wrapRelayFrame(
        grant.clientId,
        encodeRelayJson(<String, Object?>{
          'version': relayHelloVersion,
          'accountId': grant.accountId,
          'runtimeId': grant.runtimeId,
          'clientId': grant.clientId,
          'keyVersion': grant.clientKeyVersion,
          'identityPublicKey': base64UrlNoPadding(identity.publicBytes),
          'ephemeralPublicKey': base64UrlNoPadding(ephemeral.publicBytes),
          'nonce': base64UrlNoPadding(nonce),
          'grant': grant.grant,
        }),
      ),
    );
    final ack = await handshake.future.timeout(_requestTimeout);
    _relayHandshake = null;
    if (ack['version'] != relayHelloVersion ||
        ack['runtimeId'] != grant.runtimeId ||
        ack['clientId'] != grant.clientId ||
        ack['nonce'] is! String) {
      throw const FormatException('The relay handshake response is invalid.');
    }
    final runtimeStatic = decodeBase64Fixed(ack['identityPublicKey']);
    final runtimeEphemeral = decodeBase64Fixed(ack['ephemeralPublicKey']);
    final echoedNonce = decodeBase64Fixed(ack['nonce'], expectedLength: 16);
    if (!_constantTimeListEquals(nonce, echoedNonce) ||
        ack['confirmation'] is! String) {
      throw const FormatException('The relay handshake nonce is invalid.');
    }
    if (!_constantTimeListEquals(
      decodeBase64Fixed(grant.runtimePublicKey),
      runtimeStatic,
    )) {
      throw const FormatException('The relay runtime identity is invalid.');
    }
    final session = await RelayCryptoSession.derive(
      localStatic: identity,
      localEphemeral: ephemeral,
      peerStatic: runtimeStatic,
      peerEphemeral: runtimeEphemeral,
      runtimeId: grant.runtimeId,
      clientId: grant.clientId,
      nonce: nonce,
      initiator: true,
    );
    await session.verifyPeerConfirmation(
      decodeBase64Fixed(ack['confirmation']),
    );
    if (!isConnectionUsable) {
      session.close();
      throw const RuntimeConnectionLost();
    }
    _relaySession = session;
    _channel.sink.add(
      wrapRelayFrame(
        grant.clientId,
        encodeRelayJson(<String, Object?>{
          'version': relayHelloVersion,
          'confirmation': base64UrlNoPadding(await session.confirmation()),
        }),
      ),
    );
  }

  static List<int> _messageBytes(Object? raw) {
    return switch (raw) {
      String text => utf8.encode(text),
      List<int> bytes => bytes,
      _ => throw const FormatException('Relay message is not binary data.'),
    };
  }
}

List<int> decodeBase64Fixed(Object? value, {int expectedLength = 32}) {
  if (value is! String) {
    throw const FormatException('Relay key is missing.');
  }
  final decoded = base64Url.decode(base64Url.normalize(value));
  if (decoded.length != expectedLength) {
    throw const FormatException('Relay key length is invalid.');
  }
  return decoded;
}

bool _constantTimeListEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var index = 0; index < a.length; index++) {
    difference |= a[index] ^ b[index];
  }
  return difference == 0;
}
