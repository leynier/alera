import 'package:alera_mobile/src/features/accounts/domain/runtime_push_preferences.dart';

class CloudAccountProfile {
  const CloudAccountProfile({
    required this.id,
    required this.email,
    this.providers = const <String>[],
  });

  final String id;
  final String email;
  final List<String> providers;

  factory CloudAccountProfile.fromJson(Map<String, Object?> json) {
    final identityProviders = _identityProviders(json['identities']);
    return CloudAccountProfile(
      id: _requiredString(json, 'id', fallbackKey: 'accountId'),
      email: _requiredString(json, 'email', fallbackKey: 'primaryEmail'),
      providers: identityProviders.isEmpty
          ? _stringList(json['providers'])
          : identityProviders,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'id': id, 'email': email, 'providers': providers};
  }
}

class CloudAccountSession {
  const CloudAccountSession({
    required this.account,
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
    this.subscriptions = const <String, RuntimePushPreferences>{},
  });

  final CloudAccountProfile account;
  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiresAt;
  final Map<String, RuntimePushPreferences> subscriptions;

  bool expiresWithin(Duration duration, DateTime now) {
    return !accessTokenExpiresAt.isAfter(now.toUtc().add(duration));
  }

  CloudAccountSession copyWith({
    CloudAccountProfile? account,
    String? accessToken,
    String? refreshToken,
    DateTime? accessTokenExpiresAt,
    Map<String, RuntimePushPreferences>? subscriptions,
  }) {
    return CloudAccountSession(
      account: account ?? this.account,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      accessTokenExpiresAt: accessTokenExpiresAt ?? this.accessTokenExpiresAt,
      subscriptions: subscriptions ?? this.subscriptions,
    );
  }

  CloudAccountSession withRuntime(
    String runtimeId, {
    RuntimePushPreferences preferences = const RuntimePushPreferences(),
  }) {
    return copyWith(
      subscriptions: <String, RuntimePushPreferences>{
        ...subscriptions,
        runtimeId: subscriptions[runtimeId] ?? preferences,
      },
    );
  }

  factory CloudAccountSession.fromJson(Map<String, Object?> json) {
    final accountJson = _map(json['account']);
    final tokenJson = _map(json['session']);
    final subscriptionsJson = _map(json['subscriptions']);
    return CloudAccountSession(
      account: CloudAccountProfile.fromJson(
        accountJson.isEmpty ? json : accountJson,
      ),
      accessToken: _requiredString(
        tokenJson.isEmpty ? json : tokenJson,
        'accessToken',
      ),
      refreshToken: _requiredString(
        tokenJson.isEmpty ? json : tokenJson,
        'refreshToken',
      ),
      accessTokenExpiresAt: _expiresAt(tokenJson.isEmpty ? json : tokenJson),
      subscriptions: <String, RuntimePushPreferences>{
        for (final entry in subscriptionsJson.entries)
          if (entry.value is Map)
            entry.key: RuntimePushPreferences.fromJson(_map(entry.value)),
      },
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'account': account.toJson(),
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'accessTokenExpiresAt': accessTokenExpiresAt.toUtc().toIso8601String(),
      'subscriptions': <String, Object?>{
        for (final entry in subscriptions.entries)
          entry.key: entry.value.toJson(),
      },
    };
  }
}

class CloudEnrollmentResult {
  const CloudEnrollmentResult({required this.session, required this.runtimeId});

  final CloudAccountSession session;
  final String runtimeId;

  factory CloudEnrollmentResult.fromJson(Map<String, Object?> json) {
    final session = CloudAccountSession.fromJson(json);
    final runtimeId =
        _optionalString(json, 'runtimeId') ??
        _optionalString(_map(json['runtime']), 'id') ??
        _stringList(json['runtimeIds']).firstOrNull;
    if (runtimeId == null) {
      throw const FormatException('Enrollment Response Is Missing Runtime Id');
    }
    return CloudEnrollmentResult(
      session: session.withRuntime(runtimeId),
      runtimeId: runtimeId,
    );
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

String _requiredString(
  Map<String, Object?> json,
  String key, {
  String? fallbackKey,
}) {
  final value =
      _optionalString(json, key) ??
      (fallbackKey == null ? null : _optionalString(json, fallbackKey));
  if (value == null) {
    throw FormatException('Missing $key');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return <String>[
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}

List<String> _identityProviders(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((identity) => _optionalString(_map(identity), 'provider'))
      .whereType<String>()
      .toList(growable: false);
}

DateTime _expiresAt(Map<String, Object?> json) {
  final encoded = _optionalString(json, 'accessTokenExpiresAt');
  if (encoded != null) {
    return DateTime.parse(encoded).toUtc();
  }
  final expiresIn = json['expiresIn'];
  final seconds = switch (expiresIn) {
    int value => value,
    String value => int.tryParse(value),
    _ => null,
  };
  if (seconds == null) {
    throw const FormatException('Missing accessTokenExpiresAt');
  }
  return DateTime.now().toUtc().add(Duration(seconds: seconds));
}
