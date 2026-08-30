import 'package:alera_mobile/src/features/accounts/domain/runtime_push_preferences.dart';

class const CloudAccountProfile({
  required final String id,
  required final String email,
  final List<String> providers = const <String>[],
}) {
  factory fromJson(Map<String, Object?> json) {
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

class const CloudAccountSession({
  required final CloudAccountProfile account,
  required final String accessToken,
  required final String refreshToken,
  required final DateTime accessTokenExpiresAt,
  final Map<String, RuntimePushPreferences> subscriptions =
      const <String, RuntimePushPreferences>{},
}) {
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

  factory fromJson(Map<String, Object?> json) {
    final accountJson = _map(json['account']);
    final tokenJson = _map(json['session']);
    final subscriptionsJson = _map(json['subscriptions']);
    return CloudAccountSession(
      account: .fromJson(accountJson.isEmpty ? json : accountJson),
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

class const CloudRuntimeProfile({
  required final String id,
  required final String name,
  required final DateTime lastSeenAt,
  required final String relayPublicKey,
  required final int relayKeyVersion,
}) {
  factory fromJson(Map<String, Object?> json) {
    return CloudRuntimeProfile(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      lastSeenAt: DateTime.parse(_requiredString(json, 'lastSeenAt')).toUtc(),
      relayPublicKey: _requiredString(json, 'relayPublicKey'),
      relayKeyVersion: _requiredInt(json, 'relayKeyVersion'),
    );
  }
}

class const CloudAuthTransaction({
  required final String transactionId,
  required final String state,
  required final Uri authorizationUrl,
  required final DateTime expiresAt,
}) {
  factory fromJson(Map<String, Object?> json) {
    return CloudAuthTransaction(
      transactionId: _requiredString(json, 'transactionId'),
      state: _requiredString(json, 'state'),
      authorizationUrl: Uri.parse(_requiredString(json, 'authorizationUrl')),
      expiresAt: DateTime.parse(_requiredString(json, 'expiresAt')).toUtc(),
    );
  }
}

class const CloudRelayIdentityRegistration({
  required final String clientId,
  required final String clientKind,
  required final String publicKey,
  required final int keyVersion,
}) {
  factory fromJson(Map<String, Object?> json) {
    return CloudRelayIdentityRegistration(
      clientId: _requiredString(json, 'clientId'),
      clientKind: _requiredString(json, 'clientKind'),
      publicKey: _requiredString(json, 'publicKey'),
      keyVersion: _requiredInt(json, 'keyVersion'),
    );
  }
}

class const CloudRelayGrant({
  required final String grant,
  required final Uri relayUrl,
  required final int expiresIn,
  required final String accountId,
  required final String runtimeId,
  required final String clientId,
  required final String clientKind,
  required final int clientKeyVersion,
  required final String clientPublicKey,
  required final String? runtimePublicKey,
}) {
  factory fromJson(Map<String, Object?> json) {
    return CloudRelayGrant(
      grant: _requiredString(json, 'grant'),
      relayUrl: Uri.parse(_requiredString(json, 'relayUrl')),
      expiresIn: _requiredInt(json, 'expiresIn'),
      accountId: _requiredString(json, 'accountId'),
      runtimeId: _requiredString(json, 'runtimeId'),
      clientId: _requiredString(json, 'clientId'),
      clientKind: _requiredString(json, 'clientKind'),
      clientKeyVersion: _requiredInt(json, 'clientKeyVersion'),
      clientPublicKey: _requiredString(json, 'clientPublicKey'),
      runtimePublicKey: _optionalString(json, 'runtimePublicKey'),
    );
  }
}

class const CloudEnrollmentResult({
  required final CloudAccountSession session,
  required final String runtimeId,
}) {
  factory fromJson(Map<String, Object?> json) {
    final session = CloudAccountSession.fromJson(json);
    final runtimeId =
        _optionalString(json, 'runtimeId') ??
        _optionalString(_map(json['runtime']), 'id') ??
        _stringList(json['runtimeIds']).firstOrNull;
    if (runtimeId == null) {
      throw const FormatException('Enrollment response is missing runtime ID');
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

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  final parsed = switch (value) {
    int number => number,
    String encoded => int.tryParse(encoded),
    _ => null,
  };
  if (parsed == null) {
    throw FormatException('Missing $key');
  }
  return parsed;
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
