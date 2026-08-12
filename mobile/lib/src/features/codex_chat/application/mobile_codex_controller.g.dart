// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_codex_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mobileCodexClient)
final mobileCodexClientProvider = MobileCodexClientFamily._();

final class MobileCodexClientProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileCodexClient>,
          MobileCodexClient,
          FutureOr<MobileCodexClient>
        >
    with
        $FutureModifier<MobileCodexClient>,
        $FutureProvider<MobileCodexClient> {
  MobileCodexClientProvider._({
    required MobileCodexClientFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileCodexClientProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileCodexClientHash();

  @override
  String toString() {
    return r'mobileCodexClientProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MobileCodexClient> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileCodexClient> create(Ref ref) {
    final argument = this.argument as String;
    return mobileCodexClient(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileCodexClientProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileCodexClientHash() => r'1e9047dedce0d695bf53888effad4575e2eaccd4';

final class MobileCodexClientFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<MobileCodexClient>, String> {
  MobileCodexClientFamily._()
    : super(
        retry: null,
        name: r'mobileCodexClientProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileCodexClientProvider call(String hostId) =>
      MobileCodexClientProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileCodexClientProvider';
}

@ProviderFor(MobileCodexController)
final mobileCodexControllerProvider = MobileCodexControllerFamily._();

final class MobileCodexControllerProvider
    extends $AsyncNotifierProvider<MobileCodexController, MobileCodexState> {
  MobileCodexControllerProvider._({
    required MobileCodexControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileCodexControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileCodexControllerHash();

  @override
  String toString() {
    return r'mobileCodexControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileCodexController create() => MobileCodexController();

  @override
  bool operator ==(Object other) {
    return other is MobileCodexControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileCodexControllerHash() =>
    r'8a892a75d875b02867aac80fddee048af7d24b9a';

final class MobileCodexControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileCodexController,
          AsyncValue<MobileCodexState>,
          MobileCodexState,
          FutureOr<MobileCodexState>,
          (String, String)
        > {
  MobileCodexControllerFamily._()
    : super(
        retry: null,
        name: r'mobileCodexControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileCodexControllerProvider call(String hostId, String tabId) =>
      MobileCodexControllerProvider._(argument: (hostId, tabId), from: this);

  @override
  String toString() => r'mobileCodexControllerProvider';
}

abstract class _$MobileCodexController
    extends $AsyncNotifier<MobileCodexState> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get tabId => _$args.$2;

  FutureOr<MobileCodexState> build(String hostId, String tabId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<MobileCodexState>, MobileCodexState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<MobileCodexState>, MobileCodexState>,
              AsyncValue<MobileCodexState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
