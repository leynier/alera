import 'dart:convert';

import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/domain/runtime_push_preferences.dart';
import 'package:http/http.dart' as http;

class AleraCloudConfiguration {
  const AleraCloudConfiguration({
    required this.baseUri,
    this.requestTimeout = const Duration(seconds: 20),
  });

  static const String defaultBaseUrl = 'https://api.alera.build/';

  final Uri baseUri;
  final Duration requestTimeout;

  factory AleraCloudConfiguration.fromEnvironment() {
    const configured = String.fromEnvironment(
      'ALERA_CLOUD_BASE_URL',
      defaultValue: defaultBaseUrl,
    );
    final normalized = configured.endsWith('/') ? configured : '$configured/';
    return AleraCloudConfiguration(baseUri: Uri.parse(normalized));
  }
}

class AleraCloudException implements Exception {
  const AleraCloudException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

abstract interface class AleraCloudApi {
  Future<CloudEnrollmentResult> redeemEnrollment({
    required String code,
    required String deviceId,
    required String deviceName,
  });

  Future<CloudAccountProfile> accountStatus(CloudAccountSession session);

  Future<CloudAccountSession> refreshSession(CloudAccountSession session);

  Future<void> registerPushToken({
    required CloudAccountSession session,
    required String token,
    required String platform,
  });

  Future<void> deletePushToken(CloudAccountSession session);

  Future<void> putSubscription({
    required CloudAccountSession session,
    required String runtimeId,
    required RuntimePushPreferences preferences,
  });

  Future<void> deleteSubscription({
    required CloudAccountSession session,
    required String runtimeId,
  });
}

class HttpAleraCloudApi implements AleraCloudApi {
  HttpAleraCloudApi({required this.configuration, http.Client? client})
    : _client = client ?? http.Client();

  final AleraCloudConfiguration configuration;
  final http.Client _client;

  void close() => _client.close();

  @override
  Future<CloudEnrollmentResult> redeemEnrollment({
    required String code,
    required String deviceId,
    required String deviceName,
  }) async {
    final payload = await _sendJson(
      'POST',
      'v1/mobile/enrollments/redeem',
      body: <String, Object?>{
        'code': code,
        'deviceId': deviceId,
        'deviceName': deviceName,
      },
    );
    return CloudEnrollmentResult.fromJson(payload);
  }

  @override
  Future<CloudAccountProfile> accountStatus(CloudAccountSession session) async {
    final payload = await _sendJson(
      'GET',
      'v1/account',
      accessToken: session.accessToken,
    );
    final account = _map(payload['account']);
    return CloudAccountProfile.fromJson(account.isEmpty ? payload : account);
  }

  @override
  Future<CloudAccountSession> refreshSession(
    CloudAccountSession session,
  ) async {
    final payload = await _sendJson(
      'POST',
      'v1/auth/refresh',
      body: <String, Object?>{'refreshToken': session.refreshToken},
    );
    final tokenPayload = _map(payload['session']);
    final source = tokenPayload.isEmpty ? payload : tokenPayload;
    final accessToken = _requiredString(source, 'accessToken');
    final refreshToken =
        _optionalString(source, 'refreshToken') ?? session.refreshToken;
    return session.copyWith(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpiresAt: _expiration(source),
    );
  }

  @override
  Future<void> registerPushToken({
    required CloudAccountSession session,
    required String token,
    required String platform,
  }) async {
    await _sendJson(
      'PUT',
      'v1/mobile/push-token',
      accessToken: session.accessToken,
      body: <String, Object?>{'token': token, 'platform': platform},
    );
  }

  @override
  Future<void> deletePushToken(CloudAccountSession session) async {
    await _sendJson(
      'DELETE',
      'v1/mobile/push-token',
      accessToken: session.accessToken,
    );
  }

  @override
  Future<void> putSubscription({
    required CloudAccountSession session,
    required String runtimeId,
    required RuntimePushPreferences preferences,
  }) async {
    await _sendJson(
      'PUT',
      'v1/mobile/subscriptions/${Uri.encodeComponent(runtimeId)}',
      accessToken: session.accessToken,
      body: <String, Object?>{
        'categories': <String, bool>{
          'attention': preferences.attention,
          'done': preferences.done,
          'terminalExit': preferences.terminalExit,
        },
      },
    );
  }

  @override
  Future<void> deleteSubscription({
    required CloudAccountSession session,
    required String runtimeId,
  }) async {
    await _sendJson(
      'DELETE',
      'v1/mobile/subscriptions/${Uri.encodeComponent(runtimeId)}',
      accessToken: session.accessToken,
    );
  }

  Future<Map<String, Object?>> _sendJson(
    String method,
    String path, {
    String? accessToken,
    Map<String, Object?>? body,
  }) async {
    final request = http.Request(method, configuration.baseUri.resolve(path));
    request.headers['accept'] = 'application/json';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (accessToken != null) {
      request.headers['authorization'] = 'Bearer $accessToken';
    }
    final streamed = await _client
        .send(request)
        .timeout(configuration.requestTimeout);
    final response = await http.Response.fromStream(streamed);
    final decoded = response.body.trim().isEmpty
        ? const <String, Object?>{}
        : _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _map(decoded['error']);
      throw AleraCloudException(
        _optionalString(error, 'message') ??
            _optionalString(decoded, 'message') ??
            'Cloud Request Failed',
        statusCode: response.statusCode,
        code:
            _optionalString(error, 'code') ?? _optionalString(decoded, 'code'),
      );
    }
    return decoded;
  }
}

Map<String, Object?> _decodeMap(String encoded) {
  try {
    return _map(jsonDecode(encoded));
  } on FormatException {
    throw const AleraCloudException('Cloud Response Was Not Valid JSON');
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = _optionalString(json, key);
  if (value == null) {
    throw FormatException('Missing $key');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

DateTime _expiration(Map<String, Object?> json) {
  final encoded = _optionalString(json, 'accessTokenExpiresAt');
  if (encoded != null) {
    return DateTime.parse(encoded).toUtc();
  }
  final raw = json['expiresIn'];
  final seconds = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
  if (seconds == null) {
    throw const FormatException('Missing accessTokenExpiresAt');
  }
  return DateTime.now().toUtc().add(Duration(seconds: seconds));
}
