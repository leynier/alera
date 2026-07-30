import 'package:alera/src/features/account/domain/alera_account_status.dart';
import 'package:alera/src/features/account/infra/runtime_alera_account_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/uri/uri_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'alera_account_providers.g.dart';

@Riverpod(keepAlive: true)
RuntimeAleraAccountRepository aleraAccountRepository(Ref ref) {
  return RuntimeAleraAccountRepository(
    ref.watch(runtimeHostClientProvider),
    coalescer: ref.watch(runtimeChangeCoalescerProvider),
  );
}

@Riverpod(keepAlive: true)
Stream<AleraAccountStatus> aleraAccountStatus(Ref ref) {
  return ref.watch(aleraAccountRepositoryProvider).watchStatus();
}

@Riverpod(keepAlive: true)
Stream<String> aleraAccountSignInFailure(Ref ref) {
  return ref.watch(aleraAccountRepositoryProvider).watchSignInFailures();
}

@Riverpod(keepAlive: true)
class AleraAccountActions extends _$AleraAccountActions {
  @override
  FutureOr<void> build() {}

  Future<void> signIn(AleraIdentityProvider provider) {
    return _run(() async {
      final uri = await ref
          .read(aleraAccountRepositoryProvider)
          .startSignIn(provider);
      await ref.read(externalUriLauncherProvider).open(uri);
    });
  }

  Future<void> link(AleraIdentityProvider provider) {
    return _run(() async {
      final uri = await ref
          .read(aleraAccountRepositoryProvider)
          .startLink(provider);
      await ref.read(externalUriLauncherProvider).open(uri);
    });
  }

  Future<void> cancelSignIn() {
    return _run(() => ref.read(aleraAccountRepositoryProvider).cancelSignIn());
  }

  Future<void> signOut() {
    return _run(() => ref.read(aleraAccountRepositoryProvider).signOut());
  }

  Future<void> deleteAccount() {
    return _run(() => ref.read(aleraAccountRepositoryProvider).deleteAccount());
  }

  Future<void> transferRuntime(String targetAccountId) {
    return _run(
      () => ref
          .read(aleraAccountRepositoryProvider)
          .transferRuntime(targetAccountId),
    );
  }

  Future<void> updatePush(MobilePushPreferences preferences) {
    return _run(
      () => ref.read(aleraAccountRepositoryProvider).updatePush(preferences),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(action);
  }
}
