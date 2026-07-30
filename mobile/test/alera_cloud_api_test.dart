import 'dart:convert';

import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/domain/runtime_push_preferences.dart';
import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Redeems Enrollment Through The Versioned Mobile Endpoint', () async {
    late http.Request captured;
    final api = HttpAleraCloudApi(
      configuration: AleraCloudConfiguration(
        baseUri: Uri.parse('https://api.example/'),
      ),
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'runtimeId': 'runtime-1',
            'accessToken': 'access',
            'refreshToken': 'refresh',
            'expiresIn': 900,
            'account': <String, Object?>{
              'id': 'account-1',
              'email': 'dev@example.com',
            },
          }),
          200,
        );
      }),
    );

    final result = await api.redeemEnrollment(
      code: 'one-time',
      deviceId: 'device-1',
      deviceName: 'Alera Mobile',
    );

    expect(captured.url.path, '/v1/mobile/enrollments/redeem');
    expect(jsonDecode(captured.body), <String, Object?>{
      'code': 'one-time',
      'deviceId': 'device-1',
      'deviceName': 'Alera Mobile',
    });
    expect(result.runtimeId, 'runtime-1');
  });

  test('Subscription Carries Bearer And Explicit Categories', () async {
    late http.Request captured;
    final api = HttpAleraCloudApi(
      configuration: AleraCloudConfiguration(
        baseUri: Uri.parse('https://api.example/'),
      ),
      client: MockClient((request) async {
        captured = request;
        return http.Response('{}', 204);
      }),
    );

    await api.putSubscription(
      session: _session(),
      runtimeId: 'runtime/1',
      preferences: const RuntimePushPreferences(attention: true, done: true),
    );

    expect(captured.url.path, '/v1/mobile/subscriptions/runtime%2F1');
    expect(captured.headers['authorization'], 'Bearer access');
    expect(jsonDecode(captured.body), <String, Object?>{
      'categories': <String, Object?>{
        'attention': true,
        'done': true,
        'terminalExit': false,
      },
    });
  });

  test('Push Token Uses Idempotent Put And Supports Removal', () async {
    final methods = <String>[];
    final api = HttpAleraCloudApi(
      configuration: AleraCloudConfiguration(
        baseUri: Uri.parse('https://api.example/'),
      ),
      client: MockClient((request) async {
        methods.add(request.method);
        return http.Response('{}', 204);
      }),
    );

    await api.registerPushToken(
      session: _session(),
      token: 'fcm-token',
      platform: 'android',
    );
    await api.deletePushToken(_session());

    expect(methods, <String>['PUT', 'DELETE']);
  });

  test('Maps Structured Cloud Failures', () async {
    final api = HttpAleraCloudApi(
      configuration: AleraCloudConfiguration(
        baseUri: Uri.parse('https://api.example/'),
      ),
      client: MockClient(
        (_) async => http.Response(
          '{"error":{"code":"quota_exceeded","message":"Daily Quota Reached"}}',
          429,
        ),
      ),
    );

    expect(
      () => api.accountStatus(_session()),
      throwsA(
        isA<AleraCloudException>()
            .having((error) => error.statusCode, 'status', 429)
            .having((error) => error.code, 'code', 'quota_exceeded'),
      ),
    );
  });
}

CloudAccountSession _session() {
  return CloudAccountSession(
    account: const CloudAccountProfile(
      id: 'account-1',
      email: 'dev@example.com',
    ),
    accessToken: 'access',
    refreshToken: 'refresh',
    accessTokenExpiresAt: DateTime.utc(2026, 8),
  );
}
