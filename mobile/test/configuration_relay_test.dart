import 'dart:convert';
import 'dart:typed_data';
import 'package:alera_configuration/alera_configuration.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_wire.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'large snapshot and apply cross the relay without oversized envelopes',
    () async {
      ConfigurationDocument large(String tag) =>
          ConfigurationDocument.empty().withBlocks({
            'desktop': {'prompt': tag * (configurationMaxBytes - 256)},
          });
      final document = large('a');
      final base = ConfigurationRevision(revision: 1, document: large('b'));
      final pending = {'document': large('c').json, 'operationId': 'pending'};
      final snapshot = {
        'document': document.json,
        'base': base.toJson(),
        'pending': pending,
        'fingerprint': 'snapshot',
      };
      final encoded = utf8.encode(jsonEncode(snapshot));
      expect(encoded.length, greaterThan(maxRelayEnvelopeBytes));
      final uploaded = BytesBuilder();
      JsonMap? applied;
      Object? throughRelay(Object? payload) {
        final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
        final reassembler = RelayFragmentReassembler();
        Uint8List? decoded;
        for (final frame in fragmentRelayPayload(bytes)) {
          decoded = reassembler.accept(frame);
        }
        expect(decoded, bytes);
        return jsonDecode(utf8.decode(decoded!));
      }

      Future<Object?> request(String type, JsonMap input) async {
        final body = jsonMap(throughRelay({'type': type, 'payload': input}));
        final payload = jsonMap(body['payload']);
        Object? response;
        switch (type) {
          case 'configuration.transfer.start':
            response = {
              'transferId': 'transfer',
              'size': payload['action'] == 'snapshot'
                  ? encoded.length
                  : payload['size'],
            };
          case 'configuration.transfer.read':
            final offset = payload['offset'] as int;
            response = {
              'data': base64Encode(
                encoded.sublist(
                  offset,
                  (offset + 128 * 1024).clamp(0, encoded.length),
                ),
              ),
            };
          case 'configuration.transfer.chunk':
            expect(payload['offset'], uploaded.length);
            uploaded.add(base64Decode(payload['data'] as String));
            response = {};
          case 'configuration.transfer.commit':
            applied = jsonMap(jsonDecode(utf8.decode(uploaded.takeBytes())));
            response = {};
          case 'configuration.transfer.cancel':
            response = {};
          default:
            fail('Unexpected request $type');
        }
        return throughRelay(response);
      }

      final target = RuntimeConfigurationTarget(
        request: request,
        accountId: 'account',
        label: 'Connected Computer',
      );
      final actual = await target.read();
      expect(actual.document.digest, document.digest);
      expect(actual.base!.document.digest, base.document.digest);
      expect(actual.pending, pending);
      await target.apply(
        document: document,
        expectedFingerprint: actual.fingerprint,
        base: base,
        pending: pending,
      );
      expect(applied!['document'], document.json);
      expect(applied!['base'], base.toJson());
      expect(applied!['pending'], pending);
      expect(applied!['expectedFingerprint'], 'snapshot');
    },
  );
}
