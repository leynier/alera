import 'package:alera_mobile/src/features/runtime/infra/relay_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _hex(String value) {
  return <int>[
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ];
}

void main() {
  test('matches the relay crypto interoperability fixture', () async {
    final clientStatic = await RelayIdentityKeyPair.fromPrivate(
      List<int>.filled(32, 1),
    );
    final runtimeStatic = await RelayIdentityKeyPair.fromPrivate(
      List<int>.filled(32, 2),
    );
    final clientEphemeral = await RelayIdentityKeyPair.fromPrivate(
      List<int>.filled(32, 3),
    );
    final runtimeEphemeral = await RelayIdentityKeyPair.fromPrivate(
      List<int>.filled(32, 4),
    );
    final nonce = List<int>.filled(16, 5);
    final client = await RelayCryptoSession.derive(
      localStatic: clientStatic,
      localEphemeral: clientEphemeral,
      peerStatic: runtimeStatic.publicBytes,
      peerEphemeral: runtimeEphemeral.publicBytes,
      runtimeId: 'runtime',
      clientId: 'mobile',
      nonce: nonce,
      initiator: true,
    );
    final runtime = await RelayCryptoSession.derive(
      localStatic: runtimeStatic,
      localEphemeral: runtimeEphemeral,
      peerStatic: clientStatic.publicBytes,
      peerEphemeral: clientEphemeral.publicBytes,
      runtimeId: 'runtime',
      clientId: 'mobile',
      nonce: nonce,
      initiator: false,
    );

    expect(
      await client.confirmation(),
      _hex('c80fa6a2b67d10ab0cc378661750b92eea311c12c3291564ccec2998d106c2f8'),
    );
    expect(
      await runtime.confirmation(),
      _hex('c16d0c2757cd97a6de1df0974a0dad18d2ddba76cd6780fdbc804a86dd213c74'),
    );
    final envelope = await client.seal('fixed vector'.codeUnits);
    expect(
      envelope,
      _hex(
        '01000000000000000000000000000000000000000000cc8e89f9f093328be9b64129b132a563ee42f15bdb63c141b76c9bdb',
      ),
    );
    expect(await runtime.open(envelope), 'fixed vector'.codeUnits);
    await runtime.verifyPeerConfirmation(await client.confirmation());
    await client.verifyPeerConfirmation(await runtime.confirmation());
    await expectLater(
      runtime.verifyPeerConfirmation(await runtime.confirmation()),
      throwsA(isA<RelayCryptoException>()),
    );
  });

  test('serializes concurrent envelopes in each direction', () async {
    final clientStatic = await RelayIdentityKeyPair.fromPrivate(
      List<int>.filled(32, 1),
    );
    final runtimeStatic = await RelayIdentityKeyPair.fromPrivate(
      List<int>.filled(32, 2),
    );
    final clientEphemeral = await RelayIdentityKeyPair.fromPrivate(
      List<int>.filled(32, 3),
    );
    final runtimeEphemeral = await RelayIdentityKeyPair.fromPrivate(
      List<int>.filled(32, 4),
    );
    final client = await RelayCryptoSession.derive(
      localStatic: clientStatic,
      localEphemeral: clientEphemeral,
      peerStatic: runtimeStatic.publicBytes,
      peerEphemeral: runtimeEphemeral.publicBytes,
      runtimeId: 'runtime',
      clientId: 'mobile',
      nonce: List<int>.filled(16, 5),
      initiator: true,
    );
    final runtime = await RelayCryptoSession.derive(
      localStatic: runtimeStatic,
      localEphemeral: runtimeEphemeral,
      peerStatic: clientStatic.publicBytes,
      peerEphemeral: clientEphemeral.publicBytes,
      runtimeId: 'runtime',
      clientId: 'mobile',
      nonce: List<int>.filled(16, 5),
      initiator: false,
    );

    final envelopes = await Future.wait(<Future<List<int>>>[
      client.seal('first'.codeUnits),
      client.seal('second'.codeUnits),
      client.seal('third'.codeUnits),
    ]);
    final clear = await Future.wait(envelopes.map(runtime.open));

    expect(clear.map(String.fromCharCodes), <String>[
      'first',
      'second',
      'third',
    ]);
  });
}
