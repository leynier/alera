import 'dart:async';
import 'dart:convert';

import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:alera_mobile/src/features/runtime/domain/connection_attempt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('Non-JSON proxy failures retain HTTP status and Retry-After', () async {
    final api = HttpAleraCloudApi(
      configuration: AleraCloudConfiguration(
        baseUri: Uri.parse('https://cloud.test/'),
      ),
      client: _ProxyFailureClient(),
    );
    await expectLater(
      api.redeemEnrollment(
        code: 'code',
        deviceId: 'device',
        deviceName: 'Phone',
      ),
      throwsA(
        isA<AleraCloudException>()
            .having((error) => error.statusCode, 'status', 503)
            .having(
              (error) => error.retryAfter,
              'retry',
              const Duration(seconds: 90),
            ),
      ),
    );
  });
  test(
    'Cloud deadline includes an unfinished response body and aborts it',
    () async {
      final transport = _StalledBodyClient();
      final api = HttpAleraCloudApi(
        configuration: AleraCloudConfiguration(
          baseUri: Uri.parse('https://cloud.test/'),
          requestTimeout: const Duration(milliseconds: 30),
        ),
        client: transport,
      );
      await expectLater(
        api.redeemEnrollment(
          code: 'code',
          deviceId: 'device',
          deviceName: 'Phone',
        ),
        throwsA(isA<TimeoutException>()),
      );
      await transport.aborted.future.timeout(const Duration(seconds: 1));
      expect(transport.requests, 1);
    },
  );

  test('Cancelling a connection aborts the active cloud request', () async {
    final transport = _StalledBodyClient();
    final api = HttpAleraCloudApi(
      configuration: AleraCloudConfiguration(
        baseUri: Uri.parse('https://cloud.test/'),
      ),
      client: transport,
    );
    final attempt = ConnectionAttempt();
    final request = attempt.run(
      () => api.redeemEnrollment(
        code: 'code',
        deviceId: 'device',
        deviceName: 'Phone',
      ),
    );
    final assertion = expectLater(
      request,
      throwsA(
        anyOf(isA<TimeoutException>(), isA<http.RequestAbortedException>()),
      ),
    );
    await transport.started.future;
    attempt.cancel();
    await assertion;
    await transport.aborted.future;
  });
}

class _StalledBodyClient extends http.BaseClient {
  final started = Completer<void>();
  final aborted = Completer<void>();
  int requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    final stream = StreamController<List<int>>();
    unawaited(
      (request as http.Abortable).abortTrigger!.then((_) {
        aborted.complete();
        stream.addError(http.RequestAbortedException());
        unawaited(stream.close());
      }),
    );
    started.complete();
    return http.StreamedResponse(stream.stream, 200);
  }
}

class _ProxyFailureClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode('<html>Temporarily unavailable</html>')),
        503,
        headers: {'retry-after': '90'},
      );
}
