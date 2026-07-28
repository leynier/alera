import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/domain/runtime_push_preferences.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cloud_accounts_controller.g.dart';

@Riverpod(keepAlive: true)
class CloudAccountsController extends _$CloudAccountsController {
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
      throw const FormatException('Enrollment Code Is Required');
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
      throw StateError('Account Session Is Missing');
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

  Future<void> replaceSession(CloudAccountSession session) async {
    final current = await future;
    final existing = current
        .where((item) => item.account.id == session.account.id)
        .firstOrNull;
    if (existing == session) {
      return;
    }
    await ref.read(cloudAccountRepositoryProvider).saveSession(session);
    state = AsyncData(_replace(current, session));
  }

  Future<void> refreshAccount(String accountId) async {
    final current = await future;
    var session = current
        .where((item) => item.account.id == accountId)
        .firstOrNull;
    if (session == null) {
      return;
    }
    if (session.expiresWithin(
      const Duration(minutes: 5),
      DateTime.now().toUtc(),
    )) {
      session = await ref.read(aleraCloudApiProvider).refreshSession(session);
    }
    final profile = await ref
        .read(aleraCloudApiProvider)
        .accountStatus(session);
    final updated = session.copyWith(account: profile);
    await replaceSession(updated);
  }

  Future<void> removeFromThisPhone(String accountId) async {
    final current = await future;
    final session = current
        .where((item) => item.account.id == accountId)
        .firstOrNull;
    if (session == null) {
      return;
    }
    for (final runtimeId in session.subscriptions.keys) {
      await ref
          .read(aleraCloudApiProvider)
          .deleteSubscription(session: session, runtimeId: runtimeId);
    }
    await ref.read(aleraCloudApiProvider).deletePushToken(session);
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
