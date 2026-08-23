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

class CloudRuntimeProfile {
  const CloudRuntimeProfile({
    required this.id,
    required this.name,
    required this.lastSeenAt,
    required this.relayPublicKey,
    required this.relayKeyVersion,
  });

  final String id;
  final String name;
  final DateTime lastSeenAt;
  final String relayPublicKey;
  final int relayKeyVersion;

  factory CloudRuntimeProfile.fromJson(Map<String, Object?> json) {
    return CloudRuntimeProfile(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      lastSeenAt: DateTime.parse(_requiredString(json, 'lastSeenAt')).toUtc(),
      relayPublicKey: _requiredString(json, 'relayPublicKey'),
      relayKeyVersion: _requiredInt(json, 'relayKeyVersion'),
    );
  }
}

class CloudAuthTransaction {
  const CloudAuthTransaction({
    required this.transactionId,
    required this.state,
    required this.authorizationUrl,
    required this.expiresAt,
  });

  final String transactionId;
  final String state;
  final Uri authorizationUrl;
  final DateTime expiresAt;

  factory CloudAuthTransaction.fromJson(Map<String, Object?> json) {
    return CloudAuthTransaction(
      transactionId: _requiredString(json, 'transactionId'),
      state: _requiredString(json, 'state'),
      authorizationUrl: Uri.parse(_requiredString(json, 'authorizationUrl')),
      expiresAt: DateTime.parse(_requiredString(json, 'expiresAt')).toUtc(),
    );
  }
}

class CloudRelayIdentityRegistration {
  const CloudRelayIdentityRegistration({
    required this.clientId,
    required this.clientKind,
    required this.publicKey,
    required this.keyVersion,
  });

  final String clientId;
  final String clientKind;
  final String publicKey;
  final int keyVersion;

  factory CloudRelayIdentityRegistration.fromJson(Map<String, Object?> json) {
    return CloudRelayIdentityRegistration(
      clientId: _requiredString(json, 'clientId'),
      clientKind: _requiredString(json, 'clientKind'),
      publicKey: _requiredString(json, 'publicKey'),
      keyVersion: _requiredInt(json, 'keyVersion'),
    );
  }
}

class CloudRelayGrant {
  const CloudRelayGrant({
    required this.grant,
    required this.relayUrl,
    required this.expiresIn,
    required this.accountId,
    required this.runtimeId,
    required this.clientId,
    required this.clientKind,
    required this.clientKeyVersion,
    required this.clientPublicKey,
    required this.runtimePublicKey,
  });

  final String grant;
  final Uri relayUrl;
  final int expiresIn;
  final String accountId;
  final String runtimeId;
  final String clientId;
  final String clientKind;
  final int clientKeyVersion;
  final String clientPublicKey;
  final String? runtimePublicKey;

  factory CloudRelayGrant.fromJson(Map<String, Object?> json) {
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
