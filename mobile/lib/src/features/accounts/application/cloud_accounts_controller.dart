import 'dart:async';
import 'dart:convert';

import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/domain/runtime_push_preferences.dart';
import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:alera_mobile/src/features/accounts/infra/mobile_cloud_sign_in.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_crypto.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cloud_accounts_controller.g.dart';

@Riverpod(keepAlive: true)
class CloudAccountsController extends _$CloudAccountsController {
  final Map<String, Future<CloudAccountSession?>> _sessionRefreshes =
      <String, Future<CloudAccountSession?>>{};

  @override
  Future<List<CloudAccountSession>> build() {
    return ref.watch(cloudAccountRepositoryProvider).loadSessions();
  }

  Future<void> redeemEnrollment(
    String code, {
    String deviceName = 'Alera Mobile',
  }) async {
    final normalized = code.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Enrollment code is required');
    }
    final repository = ref.read(cloudAccountRepositoryProvider);
    final installationId = await repository.getOrCreateInstallationId();
    final result = await ref
        .read(aleraCloudApiProvider)
        .redeemEnrollment(
          code: normalized,
          deviceId: installationId,
          deviceName: deviceName,
        );
    final current = await future;
    final previous = current
        .where((item) => item.account.id == result.session.account.id)
        .firstOrNull;
    final merged = previous == null
        ? result.session
        : result.session.copyWith(
            subscriptions: <String, RuntimePushPreferences>{
              ...previous.subscriptions,
              ...result.session.subscriptions,
            },
          );
    await repository.saveSession(merged);
    state = AsyncData(_replace(current, merged));
  }

  Future<void> signIn(String provider) async {
    final repository = ref.read(cloudAccountRepositoryProvider);
    final installationId = await repository.getOrCreateInstallationId();
    final session = await MobileCloudSignIn(
      api: ref.read(aleraMobileAuthApiProvider),
      installationId: installationId,
    ).signIn(provider);
    await repository.saveSession(session);
    final current = await future;
    state = AsyncData(_replace(current, session));
    await _registerRelayIdentity(session, expectedClientId: installationId);
  }

  Future<List<CloudRuntimeProfile>> discoverRuntimes(String accountId) async {
    final sessions = await future;
    final session = sessions
        .where((item) => item.account.id == accountId)
        .firstOrNull;
    if (session == null) throw StateError('Account session is missing.');
    return ref.read(aleraRelayCloudApiProvider).discoverRuntimes(session);
  }

  Future<void> _registerRelayIdentity(
    CloudAccountSession session, {
    required String expectedClientId,
  }) async {
    final privateKey = await ref
        .read(cloudRelayIdentityRepositoryProvider)
        .getOrCreatePrivateKey(session.account.id);
    final identity = await RelayIdentityKeyPair.fromPrivate(
      base64Url.decode(base64Url.normalize(privateKey)),
    );
    final registration = await ref
        .read(aleraRelayCloudApiProvider)
        .registerRelayIdentity(
          session: session,
          publicKey: base64UrlNoPadding(identity.publicBytes),
          keyVersion: 1,
        );
    if (registration.clientId != expectedClientId ||
        registration.clientKind != 'mobile' ||
        registration.publicKey != base64UrlNoPadding(identity.publicBytes) ||
        registration.keyVersion != 1) {
      throw const FormatException('Cloud returned an invalid mobile identity');
    }
  }

  Future<void> updateRuntimePreferences({
    required String accountId,
    required String runtimeId,
    required RuntimePushPreferences preferences,
  }) async {
    final current = await future;
    final session = current
        .where((item) => item.account.id == accountId)
        .firstOrNull;
    if (session == null) {
      throw StateError('Account session is missing');
    }
    final updated = session.copyWith(
      subscriptions: <String, RuntimePushPreferences>{
        ...session.subscriptions,
        runtimeId: preferences,
      },
    );
    await ref.read(cloudAccountRepositoryProvider).saveSession(updated);
    state = AsyncData(_replace(current, updated));
  }

  Future<CloudAccountSession?> sessionForRequest(
    String accountId, {
    Duration refreshWithin = const Duration(minutes: 5),
  }) async {
    final pending = _sessionRefreshes[accountId];
    if (pending != null) {
      return pending;
    }
    final operation = _refreshSessionForRequest(accountId, refreshWithin);
    _sessionRefreshes[accountId] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_sessionRefreshes[accountId], operation)) {
        _sessionRefreshes.remove(accountId);
      }
    }
  }

  Future<CloudAccountSession?> _refreshSessionForRequest(
    String accountId,
    Duration refreshWithin,
  ) async {
    final current = await future;
    final existing = current
        .where((item) => item.account.id == accountId)
        .firstOrNull;
    if (existing == null ||
        !existing.expiresWithin(refreshWithin, DateTime.now().toUtc())) {
      return existing;
    }
    final refreshed = await ref
        .read(aleraCloudApiProvider)
        .refreshSession(existing);
    return _replaceIfCurrent(
      refreshed,
      expectedRefreshToken: existing.refreshToken,
    );
  }

  Future<CloudAccountSession?> _replaceIfCurrent(
    CloudAccountSession replacement, {
    required String expectedRefreshToken,
  }) async {
    final current = await future;
    final existing = current
        .where((item) => item.account.id == replacement.account.id)
        .firstOrNull;
    if (existing == null || existing.refreshToken != expectedRefreshToken) {
      return existing;
    }
    await ref.read(cloudAccountRepositoryProvider).saveSession(replacement);
    state = AsyncData(_replace(current, replacement));
    return replacement;
  }

  Future<void> refreshAccount(String accountId) async {
    final session = await sessionForRequest(accountId);
    if (session == null) {
      return;
    }
    final profile = await ref
        .read(aleraCloudApiProvider)
        .accountStatus(session);
    final updated = session.copyWith(account: profile);
    await _replaceIfCurrent(
      updated,
      expectedRefreshToken: session.refreshToken,
    );
  }

  Future<void> removeFromThisPhone(String accountId) async {
    final current = await future;
    final session = current
        .where((item) => item.account.id == accountId)
        .firstOrNull;
    if (session == null) {
      return;
    }
    final api = ref.read(aleraCloudApiProvider);
    try {
      for (final runtimeId in session.subscriptions.keys) {
        await api.deleteSubscription(session: session, runtimeId: runtimeId);
      }
      await api.deletePushToken(session);
      await api.revokeSession(session);
    } on AleraCloudException catch (error) {
      if (error.statusCode != 401) {
        rethrow;
      }
    }
    await ref.read(cloudAccountRepositoryProvider).removeSession(accountId);
    state = AsyncData(<CloudAccountSession>[
      for (final item in current)
        if (item.account.id != accountId) item,
    ]);
  }

  List<CloudAccountSession> _replace(
    List<CloudAccountSession> sessions,
    CloudAccountSession replacement,
  ) {
    return <CloudAccountSession>[
      replacement,
      for (final session in sessions)
        if (session.account.id != replacement.account.id) session,
    ];
  }
}
