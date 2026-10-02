import 'dart:async';
import 'dart:io';

import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Malformed runtime messages fail the client and pending requests',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final socketReady = Completer<WebSocket>();
      addTearDown(() async {
        if (socketReady.isCompleted) {
          await (await socketReady.future).close();
        }
        await server.close(force: true);
      });

      final subscription = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        if (!socketReady.isCompleted) socketReady.complete(socket);
        await socket.done;
      });
      addTearDown(subscription.cancel);

      final client = await MobileRuntimeClient.connect(
        'ws://${server.address.address}:${server.port}',
      );
      addTearDown(client.dispose);
      final socket = await socketReady.future.timeout(
        const Duration(seconds: 5),
      );
      final failureFuture = client.connectionFailures.first;
      socket.add('{malformed');

      final failure = await failureFuture.timeout(const Duration(seconds: 5));
      expect(failure.$1, isA<FormatException>());
      expect(client.isConnectionUsable, isFalse);
      expect(client.debugPendingRequestCount, 0);
      await expectLater(
        client.request('mobile.status.get'),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
