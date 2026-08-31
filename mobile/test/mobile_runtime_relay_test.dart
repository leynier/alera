import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:alera_mobile/src/features/runtime/domain/host_reachability.dart';

import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_crypto.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_wire.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Relay upgrade preserves transient and permanent HTTP status', () async {
    final identity = await RelayIdentityKeyPair.generate();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var status = 503;
    final listener = server.listen((request) async {
      request.response.statusCode = status;
      await request.response.close();
    });
    addTearDown(() async {
      await listener.cancel();
      await server.close(force: true);
    });
    final grant = CloudRelayGrant(
      grant: 'fixture',
      relayUrl: Uri(scheme: 'ws', host: '127.0.0.1', port: server.port),
      expiresIn: 120,
      accountId: 'a',
      runtimeId: 'r',
      clientId: 'c',
      clientKind: 'mobile',
      clientKeyVersion: 1,
      clientPublicKey: base64UrlNoPadding(identity.publicBytes),
      runtimePublicKey: base64UrlNoPadding(identity.publicBytes),
    );
    for (final code in [503, 429, 403]) {
      status = code;
      await expectLater(
        MobileRuntimeClient.connectRelay(grant: grant, identity: identity),
        throwsA(
          isA<AleraCloudException>().having(
            (error) => error.statusCode,
            'status',
            code,
          ),
        ),
      );
    }
  });
  test('Relay renews runtime then edge without reconnecting or resetting encryption', () async {
    final runtimeIdentity = await RelayIdentityKeyPair.generate();
    final mobileIdentity = await RelayIdentityKeyPair.generate();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final hellos = <Map<String, Object?>>[];
    final order = <String>[];
    final sockets = <WebSocket>[];
    final served = <Future<void>>[];
    final renewed = Completer<void>();
    final listener = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(
        request,
        protocolSelector: (protocols) => relayControlProtocol,
      );
      sockets.add(socket);
      served.add(
        _serve(
          socket,
          runtimeIdentity,
          hellos,
          renewalOrder: order,
          renewed: renewed,
        ),
      );
    });
    CloudRelayGrant grant(int seconds) => CloudRelayGrant(
      grant: _grantToken(
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + seconds,
      ),
      relayUrl: Uri.parse('ws://127.0.0.1:${server.port}'),
      expiresIn: seconds,
      accountId: 'account',
      runtimeId: 'runtime',
      clientId: 'phone',
      clientKind: 'mobile',
      clientKeyVersion: 1,
      clientPublicKey: base64UrlNoPadding(mobileIdentity.publicBytes),
      runtimePublicKey: base64UrlNoPadding(runtimeIdentity.publicBytes),
    );
    final client = await MobileRuntimeClient.connectRelay(
      grant: grant(31),
      identity: mobileIdentity,
      requestGrant: () async => grant(120),
    );
    addTearDown(() async {
      await client.dispose();
      for (final socket in sockets) {
        await socket.close();
      }
      await listener.cancel();
      await server.close(force: true);
      await Future.wait(served);
    });
    await client.authenticateRelay();
    expect(await client.requestMap('echo', {'before': true}), {'before': true});
    await renewed.future.timeout(const Duration(seconds: 5));
    expect(await client.requestMap('echo', {'after': true}), {'after': true});
    expect(order, ['runtime', 'edge']);
    expect(hellos, hasLength(1));
    expect(sockets, hasLength(1));
    expect(client.isConnectionUsable, isTrue);
    final failure = client.connectionFailures.first;
    sockets.single.add(
      wrapRelayFrame('phone', fragmentRelayPayload(.filled(70000, 0)).first),
    );
    expect(
      (await failure.timeout(const Duration(seconds: 12))).$1,
      isA<HostUnreachableException>(),
    );
    expect(client.isConnectionUsable, isFalse);
  });

  test('Relay authenticates, preserves Codex support and reconnects with fresh encryption', () async {
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
  });
}

Future<void> _serve(
  WebSocket socket,
  RelayIdentityKeyPair identity,
  List<Map<String, Object?>> hellos, {
  List<String>? renewalOrder,
  Completer<void>? renewed,
}) async {
  RelayCryptoSession? session;
  var confirmed = false;
  final fragments = RelayFragmentReassembler();
  await for (final raw in socket) {
    final wire = raw as List<int>;
    if (wire.length >= 2 && wire[0] == 0 && wire[1] == 0) {
      final request = jsonDecode(utf8.decode(wire.sublist(2))) as Map;
      renewalOrder?.add('edge');
      final token = request['grant'] as String;
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
      ) as Map;
      socket.add([
        0,
        0,
        ...utf8.encode(
          jsonEncode({
            'type': 'auth.renewed',
            'id': request['id'],
            'expiresAt': claims['exp'],
          }),
        ),
      ]);
      renewed?.complete();
      continue;
    }
    final (clientId, bytes) = unwrapRelayFrame(raw);
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
    Map<String, Object?>? renewalPayload;
    if (request['type'] == 'mobile.relayAuthorization.renew') {
      renewalOrder?.add('runtime');
      final token = payload['grant'] as String;
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
      ) as Map;
      renewalPayload = {'expiresAt': claims['exp']};
    }
    if (request['type'] == 'mobile.hello') hellos.add(payload);
    final response = await session.seal(
      utf8.encode(
        jsonEncode({
          'id': request['id'],
          'ok': true,
          'payload': request['type'] == 'mobile.hello'
              ? {
                  'binaryFrames': true,
                  'runtimeCapabilities': <String>[
                    if (renewalOrder != null) relayRenewalCapability,
                  ],
                }
              : renewalPayload ?? payload,
        }),
      ),
    );
    for (final fragment in fragmentRelayPayload(response)) {
      socket.add(wrapRelayFrame(clientId, fragment));
    }
  }
}

String _grantToken(int expiresAt) =>
    'header.${base64UrlNoPadding(utf8.encode(jsonEncode({'exp': expiresAt})))}.signature';
