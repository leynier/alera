enum AleraIdentityProvider(final String wireName, final String label) {
  google('google', 'Google'),
  github('github', 'GitHub');

  static AleraIdentityProvider? fromWireName(String value) {
    for (final provider in values) {
      if (provider.wireName == value) {
        return provider;
      }
    }
    return null;
  }
}

final class const AleraAccountDetails({
  required final String id,
  required final String email,
  required final Set<AleraIdentityProvider> providers,
  required final String runtimeId,
  required final int pushSubscriptionCount,
}) {
  factory fromJson(Map<String, Object?> json) {
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
}

final class const MobilePushPreferences({
  required final bool enabled,
  required final bool attention,
  required final bool done,
  required final bool terminalExit,
}) {
  factory fromJson(Map<String, Object?> json) {
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

final class const AleraAccountStatus({
  required final bool connected,
  required final bool signInPending,
  required final AleraAccountDetails? account,
  required final MobilePushPreferences push,
}) {
  factory fromRuntime({
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
}
