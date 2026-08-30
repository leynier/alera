import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const int relayProtocolVersion = 1;
const int relayClientToRuntime = 0;
const int relayRuntimeToClient = 1;
const int _keyBytes = 32;
const int _headerBytes = 1 + 1 + 8 + 12;

class const RelayCryptoException(final String message) implements Exception {
  @override
  String toString() => message;
}

class RelayIdentityKeyPair._(
  final List<int> privateBytes,
  final List<int> publicBytes,
) {
  static Future<RelayIdentityKeyPair> generate() async {
    return fromKeyPair(await X25519().newKeyPair());
  }

  static Future<RelayIdentityKeyPair> fromPrivate(
    List<int> privateBytes,
  ) async {
    if (privateBytes.length != _keyBytes) {
      throw const RelayCryptoException(
        'Relay identity private key is invalid.',
      );
    }
    return fromKeyPair(await X25519().newKeyPairFromSeed(privateBytes));
  }

  static Future<RelayIdentityKeyPair> fromKeyPair(SimpleKeyPair keyPair) async {
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    return RelayIdentityKeyPair._(
      List<int>.unmodifiable(privateBytes),
      List<int>.unmodifiable(publicKey.bytes),
    );
  }

  Future<SimpleKeyPair> _keyPair() {
    return X25519().newKeyPairFromSeed(privateBytes).then((value) => value);
  }
}

class RelayCryptoSession._({
  required final List<int> _sendKey,
  required final List<int> _receiveKey,
  required final List<int> _confirmationKey,
  required final List<int> _transcriptHash,
  required final int _sendDirection,
  required final int _receiveDirection,
}) {
  int _nextSendCounter = 0;
  int _nextReceiveCounter = 0;
  Future<void> _sendTail = Future<void>.value();
  Future<void> _receiveTail = Future<void>.value();
  int _queuedBytes = 0;
  bool _closed = false;

  void close() => _closed = true;

  Future<T> _bounded<T>(int bytes, Future<T> Function() operation) {
    if (_closed ||
        bytes > 1024 * 1024 ||
        _queuedBytes + bytes > 4 * 1024 * 1024) {
      return Future.error(
        const RelayCryptoException('Relay crypto queue is unavailable.'),
      );
    }
    _queuedBytes += bytes;
    return operation().whenComplete(() => _queuedBytes -= bytes);
  }

  static Future<RelayCryptoSession> derive({
    required RelayIdentityKeyPair localStatic,
    required RelayIdentityKeyPair localEphemeral,
    required List<int> peerStatic,
    required List<int> peerEphemeral,
    required String runtimeId,
    required String clientId,
    required List<int> nonce,
    required bool initiator,
  }) async {
    if (peerStatic.length != _keyBytes ||
        peerEphemeral.length != _keyBytes ||
        nonce.length != 16 ||
        runtimeId.length > 0xffff ||
        clientId.length > 0xffff) {
      throw const RelayCryptoException(
        'Relay handshake transcript is invalid.',
      );
    }
    final algorithm = X25519();
    final localStaticPair = await localStatic._keyPair();
    final localEphemeralPair = await localEphemeral._keyPair();
    final peerStaticKey = SimplePublicKey(peerStatic, type: .x25519);
    final peerEphemeralKey = SimplePublicKey(peerEphemeral, type: .x25519);

    Future<List<int>> shared(SimpleKeyPair pair, SimplePublicKey key) async {
      final secret = await algorithm.sharedSecretKey(
        keyPair: pair,
        remotePublicKey: key,
      );
      final bytes = await secret.extractBytes();
      if (bytes.every((byte) => byte == 0)) {
        throw const RelayCryptoException(
          'Relay handshake transcript is invalid.',
        );
      }
      return bytes;
    }

    final staticStatic = await shared(localStaticPair, peerStaticKey);
    final ephemeralStatic = initiator
        ? await shared(localEphemeralPair, peerStaticKey)
        : await shared(localStaticPair, peerEphemeralKey);
    final staticEphemeral = initiator
        ? await shared(localStaticPair, peerEphemeralKey)
        : await shared(localEphemeralPair, peerStaticKey);
    final ephemeralEphemeral = await shared(
      localEphemeralPair,
      peerEphemeralKey,
    );
    final initiatorStatic = initiator ? localStatic.publicBytes : peerStatic;
    final responderStatic = initiator ? peerStatic : localStatic.publicBytes;
    final initiatorEphemeral = initiator
        ? localEphemeral.publicBytes
        : peerEphemeral;
    final responderEphemeral = initiator
        ? peerEphemeral
        : localEphemeral.publicBytes;
    final transcript = _transcript(
      runtimeId,
      clientId,
      initiatorStatic,
      responderStatic,
      initiatorEphemeral,
      responderEphemeral,
      nonce,
    );
    final transcriptHash = (await Sha256().hash(transcript)).bytes;
    final ikm = <int>[
      ...staticStatic,
      ...ephemeralStatic,
      ...staticEphemeral,
      ...ephemeralEphemeral,
    ];
    final hkdf = Hkdf(hmac: .sha256(), outputLength: _keyBytes);
    Future<List<int>> key(String label) async {
      final info = <int>[
        ..._utf8('alera-relay-key:'),
        ..._utf8(label),
        ...transcriptHash,
      ];
      final derived = await hkdf.deriveKey(
        secretKey: SecretKey(ikm),
        nonce: _utf8('alera-relay-v1'),
        info: info,
      );
      return derived.extractBytes();
    }

    final sendKey = await key(
      initiator ? 'client-to-runtime' : 'runtime-to-client',
    );
    final receiveKey = await key(
      initiator ? 'runtime-to-client' : 'client-to-runtime',
    );
    final confirmationKey = await key('handshake-confirmation');
    return RelayCryptoSession._(
      sendKey: sendKey,
      receiveKey: receiveKey,
      confirmationKey: confirmationKey,
      transcriptHash: transcriptHash,
      sendDirection: initiator ? relayClientToRuntime : relayRuntimeToClient,
      receiveDirection: initiator ? relayRuntimeToClient : relayClientToRuntime,
    );
  }

  Future<List<int>> confirmation() async {
    return _confirmationForDirection(_sendDirection);
  }

  Future<void> verifyPeerConfirmation(List<int> value) async {
    final expected = await _confirmationForDirection(_receiveDirection);
    if (!_constantTimeEquals(expected, value)) {
      throw const RelayCryptoException('Relay handshake confirmation failed.');
    }
  }

  Future<List<int>> _confirmationForDirection(int direction) async {
    final role = direction == relayClientToRuntime ? 'client' : 'runtime';
    return (await Hmac.sha256().calculateMac(<int>[
      ..._utf8('alera-relay-confirmation:$role:'),
      ..._transcriptHash,
    ], secretKey: SecretKey(_confirmationKey))).bytes;
  }

  Future<Uint8List> seal(List<int> plaintext) {
    final result = _bounded(
      plaintext.length,
      () => _sendTail.then((_) {
        if (_closed) throw const RelayCryptoException('Relay session closed.');
        return _seal(plaintext);
      }),
    );
    _sendTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<Uint8List> _seal(List<int> plaintext) async {
    final counter = _nextSendCounter;
    final nonce = _nonce(_sendDirection, counter);
    final aad = _associatedData(_sendDirection, counter);
    final box = await Chacha20.poly1305Aead().encrypt(
      plaintext,
      secretKey: SecretKey(_sendKey),
      nonce: nonce,
      aad: aad,
    );
    _nextSendCounter += 1;
    return Uint8List.fromList(<int>[
      relayProtocolVersion,
      _sendDirection,
      ..._u64(counter),
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Uint8List> open(List<int> envelope) {
    final result = _bounded(
      envelope.length,
      () => _receiveTail.then((_) {
        if (_closed) throw const RelayCryptoException('Relay session closed.');
        return _open(envelope);
      }),
    );
    _receiveTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<Uint8List> _open(List<int> envelope) async {
    if (envelope.length < _headerBytes + 16 ||
        envelope[0] != relayProtocolVersion ||
        envelope[1] != _receiveDirection) {
      throw const RelayCryptoException('Relay envelope is invalid.');
    }
    final counter = _readU64(envelope.sublist(2, 10));
    if (counter != _nextReceiveCounter) {
      throw const RelayCryptoException('Relay envelope replay or counter gap.');
    }
    final expectedNonce = _nonce(_receiveDirection, counter);
    if (!_constantTimeEquals(expectedNonce, envelope.sublist(10, 22))) {
      throw const RelayCryptoException('Relay envelope nonce is invalid.');
    }
    final cipherAndMac = envelope.sublist(_headerBytes);
    final box = SecretBox(
      cipherAndMac.sublist(0, cipherAndMac.length - 16),
      nonce: expectedNonce,
      mac: Mac(cipherAndMac.sublist(cipherAndMac.length - 16)),
    );
    try {
      final clear = await Chacha20.poly1305Aead().decrypt(
        box,
        secretKey: SecretKey(_receiveKey),
        aad: _associatedData(_receiveDirection, counter),
      );
      _nextReceiveCounter += 1;
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const RelayCryptoException('Relay envelope authentication failed.');
    }
  }

  List<int> _associatedData(int direction, int counter) {
    return <int>[
      relayProtocolVersion,
      direction,
      ..._u64(counter),
      ..._transcriptHash,
    ];
  }

  static List<int> _nonce(int direction, int counter) {
    return <int>[direction, 0, 0, 0, ..._u64(counter)];
  }

  static List<int> _u64(int value) {
    final result = List<int>.filled(8, 0);
    var current = value;
    for (var index = 7; index >= 0; index--) {
      result[index] = current & 0xff;
      current >>= 8;
    }
    return result;
  }

  static int _readU64(List<int> bytes) {
    var result = 0;
    for (final byte in bytes) {
      result = (result << 8) | byte;
    }
    return result;
  }
}

List<int> _utf8(String value) => utf8.encode(value);

List<int> _transcript(
  String runtimeId,
  String clientId,
  List<int> initiatorStatic,
  List<int> responderStatic,
  List<int> initiatorEphemeral,
  List<int> responderEphemeral,
  List<int> nonce,
) {
  final result = <int>[..._utf8('ALERA-RELAY-HANDSHAKE-V1')];
  void stringPart(String value) {
    final bytes = _utf8(value);
    result.addAll(<int>[(bytes.length >> 8) & 0xff, bytes.length & 0xff]);
    result.addAll(bytes);
  }

  stringPart(runtimeId);
  stringPart(clientId);
  result.addAll(initiatorStatic);
  result.addAll(responderStatic);
  result.addAll(initiatorEphemeral);
  result.addAll(responderEphemeral);
  result.addAll(nonce);
  return result;
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var index = 0; index < a.length; index++) {
    difference |= a[index] ^ b[index];
  }
  return difference == 0;
}

String base64UrlNoPadding(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}
