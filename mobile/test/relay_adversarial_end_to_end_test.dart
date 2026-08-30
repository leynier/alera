import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_crypto.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_wire.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final origin = Platform.environment['ALERA_RELAY_TEST_ORIGIN'];
  test(
    'Blocked handshake and unread output do not stop the other six peers',
    () async {
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      final identity = await RelayIdentityKeyPair.fromPrivate(.filled(32, 7));
      Future<CloudRelayGrant> grant(String id) async {
        final response = await (await http.getUrl(
          Uri.parse('$origin/fixture/grant?role=mobile&client=$id'),
        )).close();
        return CloudRelayGrant.fromJson(
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>,
        );
      }

      final blocked = await _RawPeer.open(
        await grant('blocked'),
        identity,
        confirm: false,
      );
      final slow = await _RawPeer.open(await grant('slow'), identity);
      addTearDown(blocked.close);
      addTearDown(slow.close);
      final closedHandshake = blocked.messages.moveNext().timeout(
        const Duration(seconds: 15),
      );
      final clients = <MobileRuntimeClient>[];
      addTearDown(() async {
        for (final client in clients) {
          await client.dispose();
        }
      });
      for (var index = 0; index < 6; index++) {
        final id = 'active-$index';
        final client = await MobileRuntimeClient.connectRelay(
          grant: await grant(id),
          identity: identity,
          requestGrant: () => grant(id),
        );
        await client.authenticateRelay();
        clients.add(client);
      }
      final elapsed = Stopwatch()..start();
      var sequence = 0;
      while (elapsed.elapsed < const Duration(seconds: 12)) {
        if (sequence < 24) {
          await slow.send({
            'id': sequence + 2,
            'type': 'echo',
            'payload': {'text': 's' * 128000},
          });
        }
        await Future.wait(
          List.generate(6, (index) async {
            final payload = {
              'sequence': sequence,
              'text': 'x' * (index == 0 ? 65000 : 32),
            };
            expect(
              await clients[index].requestMap(
                'echo',
                payload,
                const Duration(seconds: 4),
              ),
              payload,
            );
          }),
        );
        sequence++;
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(await closedHandshake, isFalse);
      expect(blocked.socket.closeCode, 1013);
      expect(clients.every((client) => client.isConnectionUsable), isTrue);
      // The expired handshake must release its edge admission slot.
      final replacement = await MobileRuntimeClient.connectRelay(
        grant: await grant('replacement'),
        identity: identity,
      );
      await replacement.authenticateRelay();
      await replacement.dispose();
      // ignore: avoid_print
      print(
        jsonEncode({
          'responsivePeers': 6,
          'rounds': sequence,
          'blockedHandshakeClosed': true,
          'mobilePeakRssBytes': ProcessInfo.maxRss,
        }),
      );
    },
    skip: origin == null
        ? 'Run edge/tool/relay_integration.mjs 20 faults.'
        : false,
  );
  test(
    'Rapid replacement never feeds stale ciphertext into the new handshake',
    () async {
      final http = HttpClient();
      final clients = <MobileRuntimeClient>[];
      addTearDown(() async {
        for (final client in clients) {
          await client.dispose();
        }
        http.close(force: true);
      });
      final identity = await RelayIdentityKeyPair.fromPrivate(.filled(32, 7));
      Future<MobileRuntimeClient> connect(String id) async {
        final response = await (await http.getUrl(
          Uri.parse(origin!).replace(
            path: '/fixture/grant',
            queryParameters: {'role': 'mobile', 'client': id},
          ),
        )).close();
        final grant = CloudRelayGrant.fromJson(
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>,
        );
        final client = await MobileRuntimeClient.connectRelay(
          grant: grant,
          identity: identity,
        );
        clients.add(client);
        await client.authenticateRelay();
        return client;
      }

      final steady = await connect('steady');
      var current = await connect('replaced');
      for (var generation = 0; generation < 12; generation++) {
        final pending = List.generate(
          12,
          (index) => current
              .requestMap('echo', {
                'text': 'x' * 65000,
                'generation': generation,
                'index': index,
              })
              .then((_) => true, onError: (_) => false),
        );
        final next = await connect('replaced');
        expect(await next.requestMap('echo', {'generation': generation}), {
          'generation': generation,
        });
        expect(
          await steady.requestMap('echo', {
            'steady': generation,
          }, const Duration(seconds: 4)),
          {'steady': generation},
        );
        await current.dispose();
        await Future.wait(pending);
        current = next;
      }
      expect(steady.isConnectionUsable, isTrue);
      expect(current.isConnectionUsable, isTrue);
    },
    skip: origin == null
        ? 'Run edge/tool/relay_integration.mjs 20 faults.'
        : false,
  );
}

class _RawPeer(
  final WebSocket socket,
  final StreamIterator<dynamic> messages,
  final String id,
  final RelayCryptoSession? session,
) {
  static Future<_RawPeer> open(
    CloudRelayGrant grant,
    RelayIdentityKeyPair identity, {
    bool confirm = true,
  }) async {
    final socket = await WebSocket.connect(
      grant.relayUrl.toString(),
      headers: {'authorization': 'Bearer ${grant.grant}'},
      protocols: [relayControlProtocol],
    );
    final messages = StreamIterator(socket);
    final ephemeral = await RelayIdentityKeyPair.generate();
    final nonce = List.filled(16, 5);
    socket.add(
      wrapRelayFrame(
        grant.clientId,
        encodeRelayJson({
          'version': relayHelloVersion,
          'accountId': grant.accountId,
          'runtimeId': grant.runtimeId,
          'clientId': grant.clientId,
          'keyVersion': 1,
          'identityPublicKey': base64UrlNoPadding(identity.publicBytes),
          'ephemeralPublicKey': base64UrlNoPadding(ephemeral.publicBytes),
          'nonce': base64UrlNoPadding(nonce),
          'grant': grant.grant,
        }),
      ),
    );
    expect(
      await messages.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    final ack = decodeRelayJson(
      unwrapRelayFrame(messages.current as List<int>).$2,
    );
    if (!confirm) return _RawPeer(socket, messages, grant.clientId, null);
    final session = await RelayCryptoSession.derive(
      localStatic: identity,
      localEphemeral: ephemeral,
      peerStatic: decodeBase64Fixed(ack['identityPublicKey']),
      peerEphemeral: decodeBase64Fixed(ack['ephemeralPublicKey']),
      runtimeId: grant.runtimeId,
      clientId: grant.clientId,
      nonce: nonce,
      initiator: true,
    );
    await session.verifyPeerConfirmation(
      decodeBase64Fixed(ack['confirmation']),
    );
    socket.add(
      wrapRelayFrame(
        grant.clientId,
        encodeRelayJson({
          'version': relayHelloVersion,
          'confirmation': base64UrlNoPadding(await session.confirmation()),
        }),
      ),
    );
    final peer = _RawPeer(socket, messages, grant.clientId, session);
    await peer.send({'id': 1, 'type': 'mobile.hello', 'payload': {}});
    expect(
      await messages.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    await session.open(unwrapRelayFrame(messages.current as List<int>).$2);
    return peer;
  }

  Future<void> send(Map<String, Object?> request) async {
    if (socket.readyState != WebSocket.open) return;
    final envelope = await session!.seal(utf8.encode(jsonEncode(request)));
    for (final fragment in fragmentRelayPayload(envelope)) {
      socket.add(wrapRelayFrame(id, fragment));
    }
  }

  Future<void> close() async {
    session?.close();
    await messages.cancel();
    await socket.close().timeout(const Duration(seconds: 2), onTimeout: () {});
  }
}
