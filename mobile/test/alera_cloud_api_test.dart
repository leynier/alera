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

  test('Revokes The Remote Session Before Local Account Removal', () async {
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

    await api.revokeSession(_session());

    expect(captured.method, 'POST');
    expect(captured.url.path, '/v1/auth/revoke');
    expect(jsonDecode(captured.body), <String, Object?>{
      'refreshToken': 'refresh',
    });
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

  test('Relay Endpoints Discover Identities And Decode Grants', () async {
    final paths = <String>[];
    final api = HttpAleraCloudApi(
      configuration: AleraCloudConfiguration(
        baseUri: Uri.parse('https://api.example/'),
      ),
      client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/v1/mobile/runtimes') {
          return http.Response(
            jsonEncode(<String, Object?>{
              'runtimes': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'runtime-1',
                  'name': 'Alera Dev',
                  'lastSeenAt': '2026-08-03T00:00:00Z',
                  'relayPublicKey': 'runtime-key',
                  'relayKeyVersion': 1,
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/v1/relay/identity') {
          return http.Response(
            jsonEncode(<String, Object?>{
              'clientId': 'mobile-1',
              'clientKind': 'mobile',
              'publicKey': 'mobile-key',
              'keyVersion': 1,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'grant': 'signed-grant',
            'relayUrl': 'wss://relay.example/v1/relay/runtime-1',
            'expiresIn': 120,
            'accountId': 'account-1',
            'runtimeId': 'runtime-1',
            'clientId': 'mobile-1',
            'clientKind': 'mobile',
            'clientKeyVersion': 1,
            'clientPublicKey': 'mobile-key',
            'runtimePublicKey': 'runtime-key',
          }),
          200,
        );
      }),
    );

    final relayApi = api as AleraRelayCloudApi;
    final runtimes = await relayApi.discoverRuntimes(_session());
    final identity = await relayApi.registerRelayIdentity(
      session: _session(),
      publicKey: 'mobile-key',
      keyVersion: 1,
    );
    final grant = await relayApi.requestRelayGrant(
      session: _session(),
      runtimeId: 'runtime-1',
    );

    expect(runtimes.single.relayKeyVersion, 1);
    expect(identity.clientKind, 'mobile');
    expect(grant.runtimePublicKey, 'runtime-key');
    expect(paths, <String>[
      '/v1/mobile/runtimes',
      '/v1/relay/identity',
      '/v1/relay/grants',
    ]);
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
    accessTokenExpiresAt: .utc(2026, 8),
  );
}
