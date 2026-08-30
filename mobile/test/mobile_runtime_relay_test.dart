import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_crypto.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_wire.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Relay authenticates, preserves Codex support and reconnects with fresh encryption',
    () async {
      final runtimeIdentity = await RelayIdentityKeyPair.generate();
      final mobileIdentity = await RelayIdentityKeyPair.generate();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final hellos = <Map<String, Object?>>[];
      final connections = <Future<void>>[];
      final listener = server.listen((request) async {
        expect(request.headers.value('authorization'), 'Bearer test-grant');
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        connections.add(_serve(socket, runtimeIdentity, hellos));
      });
      addTearDown(() async {
        for (final socket in sockets) {
          await socket.close();
        }
        await listener.cancel();
        await server.close(force: true);
        await Future.wait(connections);
      });
      final grant = CloudRelayGrant(
        grant: 'test-grant',
        relayUrl: Uri.parse('ws://127.0.0.1:${server.port}'),
        expiresIn: 120,
        accountId: 'account',
        runtimeId: 'runtime',
        clientId: 'phone',
        clientKind: 'mobile',
        clientKeyVersion: 1,
        clientPublicKey: base64UrlNoPadding(mobileIdentity.publicBytes),
        runtimePublicKey: base64UrlNoPadding(runtimeIdentity.publicBytes),
      );
      for (var connection = 0; connection < 2; connection++) {
        final client = await MobileRuntimeClient.connectRelay(
          grant: grant,
          identity: mobileIdentity,
        );
        await client.authenticateRelay(cloudDeviceId: 'phone');
        expect(hellos.last['supportedTabKinds'], ['codex']);
        expect(hellos.last['cloudDeviceId'], 'phone');
        final messages = List.generate(
          4,
          (index) => '$connection:$index:${'x' * 65000}',
        );
        final results = await Future.wait(
          messages.map((text) => client.requestMap('echo', {'text': text})),
        );
        expect(results.map((result) => result['text']), messages);
        expect(client.isConnectionUsable, isTrue);
        await client.dispose();
      }
      expect(hellos, hasLength(2));
    },
  );
}

Future<void> _serve(
  WebSocket socket,
  RelayIdentityKeyPair identity,
  List<Map<String, Object?>> hellos,
) async {
  RelayCryptoSession? session;
  var confirmed = false;
  final fragments = RelayFragmentReassembler();
  await for (final raw in socket) {
    final (clientId, bytes) = unwrapRelayFrame(raw as List<int>);
    if (session == null) {
      final hello = decodeRelayJson(bytes);
      final ephemeral = await RelayIdentityKeyPair.generate();
      final nonce = decodeBase64Fixed(hello['nonce'], expectedLength: 16);
      session = await RelayCryptoSession.derive(
        localStatic: identity,
        localEphemeral: ephemeral,
        peerStatic: decodeBase64Fixed(hello['identityPublicKey']),
        peerEphemeral: decodeBase64Fixed(hello['ephemeralPublicKey']),
        runtimeId: 'runtime',
        clientId: clientId,
        nonce: nonce,
        initiator: false,
      );
      socket.add(
        wrapRelayFrame(
          clientId,
          encodeRelayJson({
            'version': relayHelloVersion,
            'runtimeId': 'runtime',
            'clientId': clientId,
            'identityPublicKey': base64UrlNoPadding(identity.publicBytes),
            'ephemeralPublicKey': base64UrlNoPadding(ephemeral.publicBytes),
            'nonce': hello['nonce'],
            'confirmation': base64UrlNoPadding(await session.confirmation()),
          }),
        ),
      );
      continue;
    }
    if (!confirmed) {
      await session.verifyPeerConfirmation(
        decodeBase64Fixed(decodeRelayJson(bytes)['confirmation']),
      );
      confirmed = true;
      continue;
    }
    final envelope = fragments.accept(bytes);
    if (envelope == null) continue;
    final request = decodeRelayJson(await session.open(envelope));
    final payload = request['payload']! as Map<String, Object?>;
    if (request['type'] == 'mobile.hello') hellos.add(payload);
    final response = await session.seal(
      utf8.encode(
        jsonEncode({
          'id': request['id'],
          'ok': true,
          'payload': request['type'] == 'mobile.hello'
              ? {'binaryFrames': true, 'runtimeCapabilities': <String>[]}
              : payload,
        }),
      ),
    );
    for (final fragment in fragmentRelayPayload(response)) {
      socket.add(wrapRelayFrame(clientId, fragment));
    }
  }
}
