enum AleraIdentityProvider {
  google('google', 'Google'),
  github('github', 'GitHub');

  const AleraIdentityProvider(this.wireName, this.label);

  final String wireName;
  final String label;

  static AleraIdentityProvider? fromWireName(String value) {
    for (final provider in values) {
      if (provider.wireName == value) {
        return provider;
      }
    }
    return null;
  }
}

final class AleraAccountDetails {
  const AleraAccountDetails({
    required this.id,
    required this.email,
    required this.providers,
    required this.runtimeId,
    required this.pushSubscriptionCount,
  });

  factory AleraAccountDetails.fromJson(Map<String, Object?> json) {
    final providers = json['providers'];
    return AleraAccountDetails(
      id: json['accountId'] as String? ?? '',
      email: json['email'] as String? ?? '',
      providers: <AleraIdentityProvider>{
        if (providers is List)
          for (final value in providers)
            if (value is String) ?AleraIdentityProvider.fromWireName(value),
      },
      runtimeId: json['runtimeId'] as String? ?? '',
      pushSubscriptionCount:
          (json['pushSubscriptionCount'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String email;
  final Set<AleraIdentityProvider> providers;
  final String runtimeId;
  final int pushSubscriptionCount;
}

final class MobilePushPreferences {
  const MobilePushPreferences({
    required this.enabled,
    required this.attention,
    required this.done,
    required this.terminalExit,
  });

  factory MobilePushPreferences.fromJson(Map<String, Object?> json) {
    return MobilePushPreferences(
      enabled: json['enabled'] == true,
      attention: json['attention'] != false,
      done: json['done'] == true,
      terminalExit: json['terminalExit'] == true,
    );
  }

  static const defaults = MobilePushPreferences(
    enabled: false,
    attention: true,
    done: false,
    terminalExit: false,
  );

  final bool enabled;
  final bool attention;
  final bool done;
  final bool terminalExit;

  MobilePushPreferences copyWith({
    bool? enabled,
    bool? attention,
    bool? done,
    bool? terminalExit,
  }) {
    return MobilePushPreferences(
      enabled: enabled ?? this.enabled,
      attention: attention ?? this.attention,
      done: done ?? this.done,
      terminalExit: terminalExit ?? this.terminalExit,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'attention': attention,
    'done': done,
    'terminalExit': terminalExit,
  };
}

final class AleraAccountStatus {
  const AleraAccountStatus({
    required this.connected,
    required this.signInPending,
    required this.account,
    required this.push,
  });

  factory AleraAccountStatus.fromRuntime({
    required Map<String, Object?> accountStatus,
    required Map<String, Object?> runtimeSettings,
  }) {
    final accountValue = accountStatus['account'];
    final pushValue = runtimeSettings['mobilePushNotifications'];
    final account = accountValue is Map
        ? AleraAccountDetails.fromJson(Map<String, Object?>.from(accountValue))
        : null;
    return AleraAccountStatus(
      connected: accountStatus['connected'] == true && account != null,
      signInPending: accountStatus['signInPending'] == true,
      account: account,
      push: pushValue is Map
          ? MobilePushPreferences.fromJson(Map<String, Object?>.from(pushValue))
          : MobilePushPreferences.defaults,
    );
  }

  final bool connected;
  final bool signInPending;
  final AleraAccountDetails? account;
  final MobilePushPreferences push;
}
