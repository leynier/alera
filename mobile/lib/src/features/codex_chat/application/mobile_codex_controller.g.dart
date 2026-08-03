// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_codex_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

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
    r'eb98124bca6db7609e38f85aafaecb0534cf163f';

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
