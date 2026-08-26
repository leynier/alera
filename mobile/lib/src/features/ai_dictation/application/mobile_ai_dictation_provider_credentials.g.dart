// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_ai_dictation_provider_credentials.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mobileAiDictationCredentialStore)
final mobileAiDictationCredentialStoreProvider =
    MobileAiDictationCredentialStoreProvider._();

final class MobileAiDictationCredentialStoreProvider
    extends
        $FunctionalProvider<
          MobileAiDictationCredentialStore,
          MobileAiDictationCredentialStore,
          MobileAiDictationCredentialStore
        >
    with $Provider<MobileAiDictationCredentialStore> {
  MobileAiDictationCredentialStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mobileAiDictationCredentialStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mobileAiDictationCredentialStoreHash();

  @$internal
  @override
  $ProviderElement<MobileAiDictationCredentialStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MobileAiDictationCredentialStore create(Ref ref) {
    return mobileAiDictationCredentialStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileAiDictationCredentialStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileAiDictationCredentialStore>(
        value,
      ),
    );
  }
}

String _$mobileAiDictationCredentialStoreHash() =>
    r'54af9499c21f2ef04c60d242eaa2ff809fc452a6';

@ProviderFor(mobileOpenAiDictationProvider)
final mobileOpenAiDictationProviderProvider =
    MobileOpenAiDictationProviderProvider._();

final class MobileOpenAiDictationProviderProvider
    extends
        $FunctionalProvider<
          MobileOpenAiDictationProvider,
          MobileOpenAiDictationProvider,
          MobileOpenAiDictationProvider
        >
    with $Provider<MobileOpenAiDictationProvider> {
  MobileOpenAiDictationProviderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mobileOpenAiDictationProviderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mobileOpenAiDictationProviderHash();

  @$internal
  @override
  $ProviderElement<MobileOpenAiDictationProvider> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MobileOpenAiDictationProvider create(Ref ref) {
    return mobileOpenAiDictationProvider(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileOpenAiDictationProvider value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileOpenAiDictationProvider>(
        value,
      ),
    );
  }
}

String _$mobileOpenAiDictationProviderHash() =>
    r'3a08240285af9b95d5db6924c762de5d89667a38';

@ProviderFor(mobileAiDictationCredentialStatus)
final mobileAiDictationCredentialStatusProvider =
    MobileAiDictationCredentialStatusFamily._();

final class MobileAiDictationCredentialStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileAiDictationCredentialStatus>,
          MobileAiDictationCredentialStatus,
          FutureOr<MobileAiDictationCredentialStatus>
        >
    with
        $FutureModifier<MobileAiDictationCredentialStatus>,
        $FutureProvider<MobileAiDictationCredentialStatus> {
  MobileAiDictationCredentialStatusProvider._({
    required MobileAiDictationCredentialStatusFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileAiDictationCredentialStatusProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() =>
      _$mobileAiDictationCredentialStatusHash();

  @override
  String toString() {
    return r'mobileAiDictationCredentialStatusProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MobileAiDictationCredentialStatus> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileAiDictationCredentialStatus> create(Ref ref) {
    final argument = this.argument as String;
    return mobileAiDictationCredentialStatus(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAiDictationCredentialStatusProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAiDictationCredentialStatusHash() =>
    r'19de98c937f1bedf51ae91a4e4413643ad868fc3';

final class MobileAiDictationCredentialStatusFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<MobileAiDictationCredentialStatus>,
          String
        > {
  MobileAiDictationCredentialStatusFamily._()
    : super(
        retry: null,
        name: r'mobileAiDictationCredentialStatusProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileAiDictationCredentialStatusProvider call(String baseUrl) =>
      MobileAiDictationCredentialStatusProvider._(
        argument: baseUrl,
        from: this,
      );

  @override
  String toString() => r'mobileAiDictationCredentialStatusProvider';
}
