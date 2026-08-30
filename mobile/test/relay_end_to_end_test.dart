import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final origin = Platform.environment['ALERA_RELAY_TEST_ORIGIN'];
  test(
    'Eight Dart clients sustain encrypted traffic through Rust and workerd renewals',
    () async {
      final http = HttpClient();
      final clients = <MobileRuntimeClient>[];
      addTearDown(() async {
        for (final client in clients) {
          await client.dispose();
        }
        http.close(force: true);
      });
      final identity = await RelayIdentityKeyPair.fromPrivate(
        List.filled(32, 7),
      );
      Future<CloudRelayGrant> grant(int client) async {
        final request = await http.getUrl(
          Uri.parse('$origin/fixture/grant?role=mobile&client=phone-$client'),
        );
        final response = await request.close();
        return CloudRelayGrant.fromJson(
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>,
        );
      }

      final connectionTimes = <int>[];
      final roundTrips = <int>[];
      for (var index = 0; index < 8; index++) {
        final watch = Stopwatch()..start();
        final initial = await grant(index);
        final client = await MobileRuntimeClient.connectRelay(
          grant: initial,
          identity: identity,
          requestGrant: () => grant(index),
        );
        await client.authenticateRelay();
        connectionTimes.add(watch.elapsedMicroseconds);
        clients.add(client);
      }
      final seconds = int.parse(
        Platform.environment['ALERA_RELAY_TEST_SECONDS'] ?? '20',
      );
      final elapsed = Stopwatch()..start();
      var sequence = 0;
      var evictions = 0;
      while (elapsed.elapsed.inSeconds < seconds) {
        if ((evictions == 0 && sequence == 1) ||
            (evictions == 1 && elapsed.elapsed.inSeconds >= 7)) {
          final request = await http.postUrl(
            Uri.parse('$origin/fixture/hibernate'),
          );
          final response = await request.close();
          expect(response.statusCode, 200);
          await response.drain<void>();
          evictions++;
        }
        await Future.wait(
          List.generate(clients.length, (index) async {
            final payload = {
              'sequence': sequence,
              'client': index,
              'text': 'x' * (index == 0 ? 65000 : 128),
            };
            final watch = Stopwatch()..start();
            expect(await clients[index].requestMap('echo', payload), payload);
            roundTrips.add(watch.elapsedMicroseconds);
            expect(clients[index].isConnectionUsable, isTrue);
          }),
        );
        sequence++;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      connectionTimes.sort();
      roundTrips.sort();
      int percentile(List<int> data, double fraction) =>
          data[((data.length - 1) * fraction).round()];
      // Aggregate timings only; fixture grants and traffic are never logged.
      // ignore: avoid_print
      print(
        jsonEncode({
          'seconds': seconds,
          'clients': clients.length,
          'responses': roundTrips.length,
          'mobilePeakRssBytes': ProcessInfo.maxRss,
          'connectionP50Us': percentile(connectionTimes, .5),
          'connectionP95Us': percentile(connectionTimes, .95),
          'roundTripP50Us': percentile(roundTrips, .5),
          'roundTripP95Us': percentile(roundTrips, .95),
        }),
      );
      final statsResponse = await (await http.getUrl(
        Uri.parse('$origin/fixture/stats'),
      )).close();
      final stats = jsonDecode(await utf8.decodeStream(statsResponse)) as Map;
      expect(stats['evictions'], 2);
      expect(stats['runtimeGrants'], greaterThanOrEqualTo(2));
      expect(stats['mobileGrants'], greaterThanOrEqualTo(16));
    },
    skip: origin == null
        ? 'Run edge/tool/relay_integration.mjs for the local cross-language fixture.'
        : false,
  );
}
