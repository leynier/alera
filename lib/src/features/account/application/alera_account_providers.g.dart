// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alera_account_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aleraAccountRepository)
final aleraAccountRepositoryProvider = AleraAccountRepositoryProvider._();

final class AleraAccountRepositoryProvider
    extends
        $FunctionalProvider<
          RuntimeAleraAccountRepository,
          RuntimeAleraAccountRepository,
          RuntimeAleraAccountRepository
        >
    with $Provider<RuntimeAleraAccountRepository> {
  AleraAccountRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aleraAccountRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aleraAccountRepositoryHash();

  @$internal
  @override
  $ProviderElement<RuntimeAleraAccountRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeAleraAccountRepository create(Ref ref) {
    return aleraAccountRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeAleraAccountRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeAleraAccountRepository>(
        value,
      ),
    );
  }
}

String _$aleraAccountRepositoryHash() =>
    r'783be54bdb5a69c311018eda5b53a75637d06148';

@ProviderFor(aleraAccountStatus)
final aleraAccountStatusProvider = AleraAccountStatusProvider._();

final class AleraAccountStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<AleraAccountStatus>,
          AleraAccountStatus,
          Stream<AleraAccountStatus>
        >
    with
        $FutureModifier<AleraAccountStatus>,
        $StreamProvider<AleraAccountStatus> {
  AleraAccountStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aleraAccountStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aleraAccountStatusHash();

  @$internal
  @override
  $StreamProviderElement<AleraAccountStatus> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<AleraAccountStatus> create(Ref ref) {
    return aleraAccountStatus(ref);
  }
}

String _$aleraAccountStatusHash() =>
    r'5ccb214a92e49863c521c2933e8a8a3be2ad538b';

@ProviderFor(aleraAccountSignInFailure)
final aleraAccountSignInFailureProvider = AleraAccountSignInFailureProvider._();

final class AleraAccountSignInFailureProvider
    extends $FunctionalProvider<AsyncValue<String>, String, Stream<String>>
    with $FutureModifier<String>, $StreamProvider<String> {
  AleraAccountSignInFailureProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aleraAccountSignInFailureProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aleraAccountSignInFailureHash();

  @$internal
  @override
  $StreamProviderElement<String> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<String> create(Ref ref) {
    return aleraAccountSignInFailure(ref);
  }
}

String _$aleraAccountSignInFailureHash() =>
    r'af5d9878d505605f98caba2ba05b505a2cf122bc';

@ProviderFor(AleraAccountActions)
final aleraAccountActionsProvider = AleraAccountActionsProvider._();

final class AleraAccountActionsProvider
    extends $AsyncNotifierProvider<AleraAccountActions, void> {
  AleraAccountActionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aleraAccountActionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aleraAccountActionsHash();

  @$internal
  @override
  AleraAccountActions create() => AleraAccountActions();
}

String _$aleraAccountActionsHash() =>
    r'4b6e3a5eb52997b0b12fb4d35aff42414525976e';

abstract class _$AleraAccountActions extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
